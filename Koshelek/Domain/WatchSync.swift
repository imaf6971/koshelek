import Foundation

/// Read-only picture of the data that the Watch app shows. The iPhone builds it and sends it through WatchConnectivity.
/// Amounts are pre-formatted on the phone so both apps always show identical numbers.
struct WatchSnapshot: Codable, Equatable {
    struct Account: Codable, Equatable, Identifiable { var id: UUID; var name: String; var balance: String }
    struct Budget: Codable, Equatable, Identifiable {
        var id: UUID; var name: String; var icon: String; var colorKey: String
        var spent: String; var limit: String; var ratio: Double
        /// 0 = normal, 1 = warning (80%+), 2 = exceeded
        var state: Int
    }
    struct Tx: Codable, Equatable, Identifiable {
        var id: UUID; var title: String; var subtitle: String; var amount: String; var kind: TxKind
        var date: Date; var icon: String; var colorKey: String
    }
    struct Category: Codable, Equatable, Identifiable { var id: UUID; var name: String; var icon: String; var colorKey: String }

    var generatedAt: Date
    var monthTitle: String
    var totalBalance: String
    var monthIncome: String
    var monthExpense: String
    var forecast: String
    var forecastNote: String
    var accounts: [Account]
    var budgets: [Budget]
    var recent: [Tx]
    var expenseCategories: [Category]
    var incomeCategories: [Category]
}

/// A transaction typed on the watch, delivered to the phone, which stores it.
struct WatchEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: TxKind
    /// Decimal as a plain string, e.g. "1250.5"
    var amount: String
    var accountID: UUID
    var categoryID: UUID?
    var date: Date
}

enum WatchChannel {
    static let snapshotKey = "snapshot"
    static let entryKey = "entry"
    static let entryIDKey = "entryID"
    static let rejectedKey = "rejectedEntry"
    static let reasonKey = "reason"

    static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
}
