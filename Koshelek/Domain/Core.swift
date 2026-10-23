import Foundation

/// Looks up a Russian string in the String Catalog.
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Looks up a format string in the String Catalog and applies arguments.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale(identifier: "ru_RU"), arguments: args)
}

enum TxKind: String, Codable, CaseIterable, Identifiable {
    case expense, income, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: L("Расход")
        case .income: L("Доход")
        case .transfer: L("Перевод")
        }
    }
}

enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? L("Расходы") : L("Доходы") }
    var txKind: TxKind { self == .expense ? .expense : .income }
}

enum Frequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: L("Каждый день")
        case .weekly: L("Каждую неделю")
        case .monthly: L("Каждый месяц")
        case .yearly: L("Каждый год")
        }
    }
    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
    }
}

/// Plain value snapshot of a transaction, used by all business logic.
struct TxRecord: Identifiable, Hashable {
    var id: UUID
    var kind: TxKind
    var amount: Decimal
    var date: Date
    var accountID: UUID?
    var toAccountID: UUID?
    var categoryID: UUID?
    var tags: [String] = []
    var note: String = ""
}

struct CategoryInfo: Identifiable, Hashable {
    var id: UUID
    var name: String
    var parentID: UUID?
    var kind: CategoryKind
}

/// Resolves the one-level category hierarchy.
struct CategoryIndex {
    let byID: [UUID: CategoryInfo]

    init(_ categories: [CategoryInfo]) {
        byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The top-level category for `id` (the category itself when it has no parent).
    func rootID(of id: UUID?) -> UUID? {
        guard let id, let c = byID[id] else { return nil }
        if let p = c.parentID, byID[p] != nil { return p }
        return c.id
    }

    /// The category plus all its direct subcategories.
    func family(of rootID: UUID) -> Set<UUID> {
        var s: Set<UUID> = [rootID]
        for c in byID.values where c.parentID == rootID { s.insert(c.id) }
        return s
    }

    func name(of id: UUID?) -> String {
        guard let id, let c = byID[id] else { return L("Без категории") }
        return c.name
    }
}

extension Decimal {
    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var result = Decimal(), value = self
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
