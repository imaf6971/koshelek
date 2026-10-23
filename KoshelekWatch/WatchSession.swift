import Foundation
import Observation
import OSLog
import WatchConnectivity

/// Watch side of the connection: keeps the last snapshot from the phone and delivers new entries to it.
@Observable
final class WatchSession: NSObject, WCSessionDelegate {
    /// DEBUG only: appends a line to Documents/debug.log so the connection can be inspected from the Mac.
    private func trace(_ line: String) {
        log.info("\(line)")
        #if DEBUG
        let url = URL.documentsDirectory.appending(path: "debug.log")
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
        #endif
    }

    static let shared = WatchSession()

    private(set) var snapshot: WatchSnapshot?
    /// Entries typed here that the phone has not confirmed yet.
    private(set) var pending: [WatchEntry] = []
    /// Entries the phone refused (for example the account was deleted), with the reason to show.
    private(set) var failed: [String] = []

    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.imaf6971.koshelek.watch", category: "watch-sync")

    override init() {
        super.init()
        if let data = defaults.data(forKey: "snapshot") { snapshot = try? WatchChannel.decoder.decode(WatchSnapshot.self, from: data) }
        if let data = defaults.data(forKey: "pending") { pending = (try? WatchChannel.decoder.decode([WatchEntry].self, from: data)) ?? [] }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleSnapshot") { snapshot = .sample }
        #endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func submit(_ entry: WatchEntry) {
        pending.append(entry)
        savePending()
        let session = WCSession.default
        trace("entry submitted: state=\(session.activationState.rawValue) companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable)")
        if let data = try? WatchChannel.encoder.encode(entry) {
            // Background queue: the phone stores it when it next runs, even if this app is closed by then.
            session.transferUserInfo([WatchChannel.entryKey: data, WatchChannel.entryIDKey: entry.id.uuidString])
        }
        flushPending()
    }

    /// Delivers every unconfirmed entry right away when the phone app is reachable. The phone ignores entries it already has.
    private func flushPending() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        for entry in pending {
            guard let data = try? WatchChannel.encoder.encode(entry) else { continue }
            session.sendMessage([WatchChannel.entryKey: data, WatchChannel.entryIDKey: entry.id.uuidString], replyHandler: { [weak self] reply in
                DispatchQueue.main.async {
                    if reply["ok"] as? Bool == false {
                        self?.reject(entry.id, reason: reply[WatchChannel.reasonKey] as? String ?? L("Телефон не принял операцию"))
                    } else {
                        self?.confirm(entry.id)
                    }
                }
            }, errorHandler: { [weak self] error in
                self?.trace("sendMessage failed: \(error.localizedDescription)")
            })
        }
    }

    /// The phone refused the entry: stop retrying and keep a message for the user.
    private func reject(_ id: UUID, reason: String) {
        guard let entry = pending.first(where: { $0.id == id }) else { return }
        failed.append(LF("Не принято: %@ (%@)", NSDecimalNumber(string: entry.amount).stringValue, reason))
        confirm(id)
    }

    func dismissFailures() { failed.removeAll() }

    private func confirm(_ id: UUID) {
        pending.removeAll { $0.id == id }
        savePending()
    }

    private func savePending() {
        defaults.set(try? WatchChannel.encoder.encode(pending), forKey: "pending")
    }

    private func accept(_ context: [String: Any]) {
        guard let data = context[WatchChannel.snapshotKey] as? Data,
              let new = try? WatchChannel.decoder.decode(WatchSnapshot.self, from: data) else { return }
        DispatchQueue.main.async {
            self.snapshot = new
            self.defaults.set(data, forKey: "snapshot")
            // An entry that shows up in the phone's data has certainly arrived.
            let known = Set(new.recent.map(\.id))
            if self.pending.contains(where: { known.contains($0.id) }) {
                self.pending.removeAll { known.contains($0.id) }
                self.savePending()
            }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        trace("activated: state=\(activationState.rawValue) companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "none")")
        accept(session.receivedApplicationContext)
        DispatchQueue.main.async { self.flushPending() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        trace("reachability changed: reachable=\(session.isReachable)")
        DispatchQueue.main.async { self.flushPending() }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = (userInfo[WatchChannel.rejectedKey] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let reason = userInfo[WatchChannel.reasonKey] as? String ?? L("Телефон не принял операцию")
        DispatchQueue.main.async { self.reject(id, reason: reason) }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        // Not proof that the phone stored the entry, so pending is cleared only on the phone's confirmation.
        trace("transfer finished: error=\(error?.localizedDescription ?? "none")")
    }
}
