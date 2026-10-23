import Foundation
import SwiftData

extension Sequence where Element: PersistentModel {
    /// Objects that are still in the store. SwiftData views may briefly hold references to objects that were just deleted;
    /// reading any attribute of those crashes, so every list a view iterates should be filtered through this first.
    var live: [Element] { filter { $0.modelContext != nil } }
}

extension Sequence where Element == Transaction {
    /// Snapshots of live transactions; objects already removed from the store are skipped.
    var records: [TxRecord] { live.map(\.record) }
}

/// Replaces the whole data set safely: the UI is taken off screen first, so no view reads objects that are being deleted.
enum DataReplacement {
    @MainActor
    static func run(settings: AppSettings, _ work: @escaping @MainActor () -> Void) {
        settings.isReplacingData = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            work()
            try? await Task.sleep(nanoseconds: 150_000_000)
            settings.isReplacingData = false
        }
    }
}

/// Persistence operations that touch several models at once.
enum Store {
    // MARK: Accounts

    /// Removes an account. Its transactions are moved to `target` or deleted. Transfers that would become self-transfers are deleted.
    static func deleteAccount(_ account: Account, moveTransactionsTo target: Account?, in context: ModelContext) {
        let outgoing = account.transactions
        let incoming = account.incomingTransfers
        if let target {
            for t in outgoing {
                if t.kind == .transfer, t.toAccount?.id == target.id { context.delete(t) } else { t.account = target }
            }
            for t in incoming {
                if t.account?.id == target.id { context.delete(t) } else { t.toAccount = target }
            }
            for r in account.rules { r.account = target }
        } else {
            for t in outgoing + incoming { context.delete(t) }
            for r in account.rules { context.delete(r) }
        }
        context.delete(account)
        context.saveOrReport()
    }

    // MARK: Categories

    /// Removes a category together with its subcategories. Transactions are moved to `target` (nil = uncategorized) or deleted.
    static func deleteCategory(_ category: Category, moveTransactionsTo target: Category?, deleteTransactions: Bool, in context: ModelContext) {
        let family = [category] + category.children
        for c in family {
            for t in c.transactions {
                if deleteTransactions { context.delete(t) } else { t.category = target }
            }
            for r in c.rules { if deleteTransactions { context.delete(r) } else { r.category = target } }
            for b in c.budgets { context.delete(b) }
        }
        for c in category.children { context.delete(c) }
        context.delete(category)
        context.saveOrReport()
    }

    /// Deletes every object, one by one. Batch deletes (`delete(model:)`) fail silently on relationships with nullify inverses.
    static func wipeAll(in context: ModelContext) {
        func deleteAll<T: PersistentModel>(_ type: T.Type) {
            (try? context.fetch(FetchDescriptor<T>()))?.forEach(context.delete)
        }
        deleteAll(Transaction.self)
        deleteAll(GoalContribution.self)
        deleteAll(SavingsGoal.self)
        deleteAll(Budget.self)
        deleteAll(RecurringRule.self)
        deleteAll(Category.self)
        deleteAll(Account.self)
        context.saveOrReport()
    }
}
