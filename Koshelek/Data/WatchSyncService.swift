import Foundation
import SwiftData
import OSLog
import WatchConnectivity

/// Stores transactions that were typed on the Apple Watch.
enum WatchEntryHandler {
    enum Outcome: Equatable {
        case applied
        /// Already stored earlier (a retry of the same entry): nothing to do, the watch can stop retrying.
        case duplicate
        /// Cannot be stored; the text says why, and the watch tells the user.
        case rejected(String)

        var isAccepted: Bool { if case .rejected = self { return false } else { return true } }
    }

    @MainActor @discardableResult
    static func apply(_ entry: WatchEntry, in context: ModelContext, settings: AppSettings? = nil) -> Outcome {
        let id = entry.id
        if ((try? context.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0 { return .duplicate }
        guard entry.kind != .transfer else { return .rejected(L("Переводы с часов не поддерживаются")) }
        guard let amount = Decimal(string: entry.amount, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            return .rejected(L("Неверная сумма"))
        }
        let accountID = entry.accountID
        guard let account = try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.id == accountID })).first, !account.isArchived else {
            return .rejected(L("Счёт удалён или в архиве"))
        }
        var category: Category?
        if let cid = entry.categoryID {
            // A category that no longer exists simply leaves the entry uncategorized; the money is still recorded.
            category = try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.id == cid })).first
        }
        let tx = Transaction(id: entry.id, kind: entry.kind, amount: amount, date: entry.date, account: account, category: category)
        context.insert(tx)
        context.saveOrReport()
        if let settings { BudgetNotifier.checkExceeded(after: tx, in: context, settings: settings) }
        return .applied
    }
}

/// iPhone side of the Watch connection: pushes the data snapshot and receives entries typed on the watch.
@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private let log = Logger(subsystem: "com.imaf6971.koshelek", category: "watch-sync")
    private var container: ModelContainer?
    private var settings: AppSettings?
    private var pending: Task<Void, Never>?

    func start(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated { session.activate() } else { schedulePush() }
    }

    /// Debounced: many saves in a row produce a single update.
    func schedulePush() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    func push() {
        guard WCSession.isSupported(), let container, let settings, settings.hasOnboarded, !settings.isReplacingData else { return }
        let session = WCSession.default
        // isWatchAppInstalled is not required: if the counterpart is missing, the send below fails and is logged.
        guard session.activationState == .activated, session.isPaired else {
            log.info("push skipped: state=\(session.activationState.rawValue) paired=\(session.isPaired)")
            return
        }
        let context = container.mainContext
        let snapshot = WatchSnapshotBuilder.make(
            accounts: (try? context.fetch(FetchDescriptor<Account>())) ?? [],
            categories: (try? context.fetch(FetchDescriptor<Category>())) ?? [],
            transactions: (try? context.fetch(FetchDescriptor<Transaction>())) ?? [],
            budgets: (try? context.fetch(FetchDescriptor<Budget>())) ?? [],
            rules: (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? [],
            money: settings.money)
        guard let data = try? WatchChannel.encoder.encode(snapshot) else { return }
        do {
            try session.updateApplicationContext([WatchChannel.snapshotKey: data])
            log.info("snapshot sent: \(data.count) bytes")
        } catch {
            log.error("updateApplicationContext failed: \(error.localizedDescription)")
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.log.info("activated: state=\(activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
            self.schedulePush()
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.schedulePush() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.log.info("reachability changed: reachable=\(session.isReachable)") }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchChannel.entryKey] as? Data,
              let entry = try? WatchChannel.decoder.decode(WatchEntry.self, from: data) else {
            replyHandler(["ok": false, WatchChannel.reasonKey: L("Неверные данные")])
            return
        }
        Task { @MainActor in
            guard let container = self.container else {
                self.log.error("message received before the store was ready")
                replyHandler(["ok": false, WatchChannel.reasonKey: L("Приложение ещё не готово, попробуйте позже")])
                return
            }
            let outcome = WatchEntryHandler.apply(entry, in: container.mainContext, settings: self.settings)
            self.log.info("message entry \(entry.id.uuidString) outcome=\(String(describing: outcome))")
            if outcome == .applied { self.schedulePush() }
            switch outcome {
            case .rejected(let reason): replyHandler(["ok": false, WatchChannel.reasonKey: reason])
            default: replyHandler(["ok": true])
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchChannel.entryKey] as? Data,
              let entry = try? WatchChannel.decoder.decode(WatchEntry.self, from: data) else { return }
        Task { @MainActor in
            guard let container = self.container else { return }
            let outcome = WatchEntryHandler.apply(entry, in: container.mainContext, settings: self.settings)
            self.log.info("queued entry \(entry.id.uuidString) outcome=\(String(describing: outcome))")
            switch outcome {
            case .applied: self.schedulePush()
            case .duplicate: break
            case .rejected(let reason):
                // Tell the watch, so it does not keep the entry as "waiting" forever.
                WCSession.default.transferUserInfo([WatchChannel.rejectedKey: entry.id.uuidString, WatchChannel.reasonKey: reason])
            }
        }
    }
}
