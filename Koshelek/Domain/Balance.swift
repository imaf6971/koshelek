import Foundation

enum BalanceCalculator {
    /// Balance of every account: initial balance plus income, minus expenses, with transfers moving money between accounts.
    static func balances(initial: [UUID: Decimal], transactions: [TxRecord]) -> [UUID: Decimal] {
        var result = initial
        for t in transactions {
            switch t.kind {
            case .income:
                if let a = t.accountID, result[a] != nil { result[a]! += t.amount }
            case .expense:
                if let a = t.accountID, result[a] != nil { result[a]! -= t.amount }
            case .transfer:
                if let a = t.accountID, result[a] != nil { result[a]! -= t.amount }
                if let b = t.toAccountID, result[b] != nil { result[b]! += t.amount }
            }
        }
        return result
    }

    static func total(_ balances: [UUID: Decimal]) -> Decimal {
        balances.values.reduce(0, +)
    }
}
