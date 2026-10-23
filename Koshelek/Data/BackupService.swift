import Foundation
import SwiftData

struct BackupFile: Codable {
    struct AccountDTO: Codable { var id: UUID; var name, icon, colorKey: String; var initialBalance: String; var sortOrder: Int; var isArchived: Bool }
    struct CategoryDTO: Codable { var id: UUID; var name, icon, colorKey: String; var kind: CategoryKind; var sortOrder: Int; var isArchived: Bool; var parentID: UUID? }
    struct TransactionDTO: Codable {
        var id: UUID; var kind: TxKind; var amount: String; var date: Date; var note: String; var tags: [String]
        var accountID, toAccountID, categoryID: UUID?; var ruleID: UUID?; var occurrenceDate: Date?
    }
    struct RuleDTO: Codable {
        var id: UUID; var kind: TxKind; var amount: String; var note: String; var frequency: Frequency
        var startDate: Date; var endDate, lastGeneratedDate: Date?; var isActive: Bool; var accountID, categoryID: UUID?
    }
    struct BudgetDTO: Codable { var id: UUID; var monthlyLimit: String; var categoryID: UUID? }
    struct GoalDTO: Codable { var id: UUID; var name, icon, colorKey: String; var targetAmount: String; var deadline: Date?; var createdAt: Date }
    struct ContributionDTO: Codable { var id: UUID; var amount: String; var date: Date; var note: String; var goalID: UUID? }
    struct SettingsDTO: Codable { var currency: Currency; var theme: ThemeChoice; var budgetNotifications: Bool }

    static let currentVersion = 1
    var app = "koshelek"
    var formatVersion = BackupFile.currentVersion
    var exportedAt = Date()
    var settings: SettingsDTO
    var accounts: [AccountDTO]
    var categories: [CategoryDTO]
    var transactions: [TransactionDTO]
    var rules: [RuleDTO]
    var budgets: [BudgetDTO]
    var goals: [GoalDTO]
    var contributions: [ContributionDTO]
}

enum BackupError: LocalizedError {
    case unreadable, wrongApp, newerVersion(Int), invalid(String), safetyCopyFailed
    var errorDescription: String? {
        switch self {
        case .safetyCopyFailed: L("Не удалось сохранить копию текущих данных, поэтому они не изменены. Проверьте свободное место на устройстве.")
        case .unreadable: L("Файл не удалось прочитать: это не резервная копия «Кошелька».")
        case .wrongApp: L("Этот файл создан не «Кошельком».")
        case .newerVersion(let v): LF("Копия создана более новой версией приложения (формат %d).", v)
        case .invalid(let s): LF("Файл повреждён: %@", s)
        }
    }
}

enum BackupService {
    private static func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    private static func str(_ d: Decimal) -> String { NSDecimalNumber(decimal: d).stringValue }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func makeBackup(in context: ModelContext, settings: AppSettings) throws -> Data {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let categories = try context.fetch(FetchDescriptor<Category>())
        let txs = try context.fetch(FetchDescriptor<Transaction>())
        let rules = try context.fetch(FetchDescriptor<RecurringRule>())
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let goals = try context.fetch(FetchDescriptor<SavingsGoal>())
        let contributions = try context.fetch(FetchDescriptor<GoalContribution>())
        let file = BackupFile(
            settings: .init(currency: settings.currency, theme: settings.theme, budgetNotifications: settings.budgetNotifications),
            accounts: accounts.map { .init(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey, initialBalance: str($0.initialBalance), sortOrder: $0.sortOrder, isArchived: $0.isArchived) },
            categories: categories.map { .init(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey, kind: $0.kind, sortOrder: $0.sortOrder, isArchived: $0.isArchived, parentID: $0.parent?.id) },
            transactions: txs.map { .init(id: $0.id, kind: $0.kind, amount: str($0.amount), date: $0.date, note: $0.note, tags: $0.tags, accountID: $0.account?.id, toAccountID: $0.toAccount?.id, categoryID: $0.category?.id, ruleID: $0.ruleID, occurrenceDate: $0.occurrenceDate) },
            rules: rules.map { .init(id: $0.id, kind: $0.kind, amount: str($0.amount), note: $0.note, frequency: $0.frequency, startDate: $0.startDate, endDate: $0.endDate, lastGeneratedDate: $0.lastGeneratedDate, isActive: $0.isActive, accountID: $0.account?.id, categoryID: $0.category?.id) },
            budgets: budgets.map { .init(id: $0.id, monthlyLimit: str($0.monthlyLimit), categoryID: $0.category?.id) },
            goals: goals.map { .init(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey, targetAmount: str($0.targetAmount), deadline: $0.deadline, createdAt: $0.createdAt) },
            contributions: contributions.map { .init(id: $0.id, amount: str($0.amount), date: $0.date, note: $0.note, goalID: $0.goal?.id) })
        return try encoder.encode(file)
    }

    /// Decodes and checks a backup file without touching the store.
    static func validate(_ data: Data) throws -> BackupFile {
        let file: BackupFile
        do { file = try decoder.decode(BackupFile.self, from: data) } catch { throw BackupError.unreadable }
        guard file.app == "koshelek" else { throw BackupError.wrongApp }
        guard file.formatVersion <= BackupFile.currentVersion else { throw BackupError.newerVersion(file.formatVersion) }
        guard file.formatVersion >= 1 else { throw BackupError.invalid(L("неизвестная версия формата")) }

        func unique<T>(_ items: [T], _ id: (T) -> UUID, _ what: String) throws -> Set<UUID> {
            let ids = items.map(id)
            guard Set(ids).count == ids.count else { throw BackupError.invalid(LF("повторяющиеся идентификаторы: %@", what)) }
            return Set(ids)
        }
        let accountIDs = try unique(file.accounts, \.id, L("счета"))
        let categoryIDs = try unique(file.categories, \.id, L("категории"))
        let goalIDs = try unique(file.goals, \.id, L("цели"))
        _ = try unique(file.transactions, \.id, L("операции"))
        let ruleIDs = try unique(file.rules, \.id, L("регулярные платежи"))

        let amounts = file.accounts.map(\.initialBalance) + file.transactions.map(\.amount) + file.rules.map(\.amount)
            + file.budgets.map(\.monthlyLimit) + file.goals.map(\.targetAmount) + file.contributions.map(\.amount)
        for a in amounts where Decimal(string: a, locale: Locale(identifier: "en_US_POSIX")) == nil { throw BackupError.invalid(LF("неверная сумма «%@»", a)) }

        let categoriesByID = Dictionary(file.categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for c in file.categories {
            guard let p = c.parentID else { continue }
            guard let parent = categoriesByID[p] else { throw BackupError.invalid(L("подкатегория без родителя")) }
            // The app supports one level of nesting, within one kind.
            if p == c.id || parent.parentID != nil || parent.kind != c.kind { throw BackupError.invalid(L("неверная иерархия категорий")) }
        }
        for t in file.transactions {
            if let a = t.accountID, !accountIDs.contains(a) { throw BackupError.invalid(L("операция ссылается на отсутствующий счёт")) }
            if let a = t.toAccountID, !accountIDs.contains(a) { throw BackupError.invalid(L("перевод ссылается на отсутствующий счёт")) }
            if let c = t.categoryID, !categoryIDs.contains(c) { throw BackupError.invalid(L("операция ссылается на отсутствующую категорию")) }
            if t.kind == .transfer, t.toAccountID == nil { throw BackupError.invalid(L("перевод без счёта зачисления")) }
            if let r = t.ruleID, !ruleIDs.contains(r) { /* rule may have been deleted: harmless */ _ = r }
        }
        for r in file.rules {
            if let a = r.accountID, !accountIDs.contains(a) { throw BackupError.invalid(L("платёж ссылается на отсутствующий счёт")) }
            if let c = r.categoryID, !categoryIDs.contains(c) { throw BackupError.invalid(L("платёж ссылается на отсутствующую категорию")) }
        }
        for b in file.budgets { if let c = b.categoryID, !categoryIDs.contains(c) { throw BackupError.invalid(L("бюджет ссылается на отсутствующую категорию")) } }
        for c in file.contributions { if let g = c.goalID, !goalIDs.contains(g) { throw BackupError.invalid(L("взнос ссылается на отсутствующую цель")) } }
        return file
    }

    /// Folder with automatic safety copies made right before data is replaced or erased.
    static var safetyDirectory: URL {
        URL.documentsDirectory.appending(path: "AutoBackups", directoryHint: .isDirectory)
    }

    /// Writes the current data to a timestamped file and keeps only the newest few. Returns the data it wrote,
    /// or nil when the copy could not be made or saved to disk (callers must then not replace the data).
    @discardableResult
    static func writeSafetyBackup(in context: ModelContext, settings: AppSettings, reason: String) -> Data? {
        guard let data = try? makeBackup(in: context, settings: settings) else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: safetyDirectory, withIntermediateDirectories: true)
        let url = safetyDirectory.appending(path: "Koshelek-\(reason)-\(FileStamp.string("yyyy-MM-dd-HHmmss")).json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        // Keep the newest five by modification date. Sorting by name would group files by `reason` and could
        // delete the copy that was just written.
        func modified(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        let old = ((try? fm.contentsOfDirectory(at: safetyDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != url.lastPathComponent }
            .sorted { modified($0) > modified($1) }
            .dropFirst(4)
        old.forEach { try? fm.removeItem(at: $0) }
        return data
    }

    /// Restores a backup after saving a safety copy of the current data; if the restore fails, puts the previous data back.
    /// Refuses to start when the safety copy cannot be written, so the current data is never replaced without a way back.
    static func restoreSafely(_ file: BackupFile, in context: ModelContext, settings: AppSettings) throws {
        guard let safety = writeSafetyBackup(in: context, settings: settings, reason: "before-restore") else {
            throw BackupError.safetyCopyFailed
        }
        do {
            try restore(file, in: context, settings: settings)
        } catch {
            context.rollback()
            if let previous = try? validate(safety) { try? restore(previous, in: context, settings: settings) }
            throw error
        }
    }

    /// Replaces all data with the contents of a validated backup.
    static func restore(_ file: BackupFile, in context: ModelContext, settings: AppSettings) throws {
        Store.wipeAll(in: context)
        var accounts: [UUID: Account] = [:], categories: [UUID: Category] = [:], goals: [UUID: SavingsGoal] = [:]
        for a in file.accounts {
            let m = Account(id: a.id, name: a.name, icon: a.icon, colorKey: a.colorKey, initialBalance: dec(a.initialBalance), sortOrder: a.sortOrder)
            m.isArchived = a.isArchived
            context.insert(m); accounts[a.id] = m
        }
        for c in file.categories {
            let m = Category(id: c.id, name: c.name, icon: c.icon, colorKey: c.colorKey, kind: c.kind, sortOrder: c.sortOrder)
            m.isArchived = c.isArchived
            context.insert(m); categories[c.id] = m
        }
        for c in file.categories { if let p = c.parentID { categories[c.id]?.parent = categories[p] } }
        for g in file.goals {
            let m = SavingsGoal(id: g.id, name: g.name, icon: g.icon, colorKey: g.colorKey, targetAmount: dec(g.targetAmount), deadline: g.deadline)
            m.createdAt = g.createdAt
            context.insert(m); goals[g.id] = m
        }
        for c in file.contributions { context.insert(GoalContribution(id: c.id, amount: dec(c.amount), date: c.date, note: c.note, goal: c.goalID.flatMap { goals[$0] })) }
        for t in file.transactions {
            context.insert(Transaction(id: t.id, kind: t.kind, amount: dec(t.amount), date: t.date, note: t.note, tags: t.tags,
                                       account: t.accountID.flatMap { accounts[$0] }, toAccount: t.toAccountID.flatMap { accounts[$0] },
                                       category: t.categoryID.flatMap { categories[$0] }, ruleID: t.ruleID, occurrenceDate: t.occurrenceDate))
        }
        for r in file.rules {
            let m = RecurringRule(id: r.id, kind: r.kind, amount: dec(r.amount), note: r.note, frequency: r.frequency, startDate: r.startDate, endDate: r.endDate,
                                  account: r.accountID.flatMap { accounts[$0] }, category: r.categoryID.flatMap { categories[$0] })
            m.lastGeneratedDate = r.lastGeneratedDate; m.isActive = r.isActive
            context.insert(m)
        }
        for b in file.budgets { context.insert(Budget(id: b.id, monthlyLimit: dec(b.monthlyLimit), category: b.categoryID.flatMap { categories[$0] })) }
        try context.save()
        settings.currency = file.settings.currency
        settings.theme = file.settings.theme
        settings.budgetNotifications = file.settings.budgetNotifications
        settings.hasOnboarded = true
    }
}
