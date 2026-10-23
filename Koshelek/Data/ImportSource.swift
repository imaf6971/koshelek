import Foundation

/// A transaction parsed from an external source (e.g. a bank statement), not yet matched to accounts and categories.
struct ImportedTransaction: Hashable {
    var date: Date
    var amount: Decimal          // signed: negative = expense
    var note: String
    var categoryHint: String?
}

/// Extension point for importers (CSV from bank statements will be added later as a conforming type).
protocol ImportSource {
    var displayName: String { get }
    func parse(_ data: Data) throws -> [ImportedTransaction]
}
