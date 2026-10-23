import Foundation
import SwiftData

/// Builds the data picture for the Apple Watch from the SwiftData models.
enum WatchSnapshotBuilder {
    static func make(accounts: [Account], categories: [Category], transactions: [Transaction], budgets: [Budget],
                     rules: [RecurringRule], money: MoneyFormatter, now: Date = Date()) -> WatchSnapshot {
        let live = transactions.filter { $0.modelContext != nil }
        let records = live.map(\.record)
        let active = accounts.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        let balances = BalanceCalculator.balances(initial: Dictionary(active.map { ($0.id, $0.initialBalance) }, uniquingKeysWith: { a, _ in a }), transactions: records)
        let month = Period.containing(now, kind: .month)
        let index = CategoryIndex(categories.map(\.info))

        let budgetRows: [WatchSnapshot.Budget] = budgets.compactMap { b in
            guard let c = b.category else { return nil }
            let p = BudgetEvaluator.progress(limit: b.monthlyLimit, spent: BudgetEvaluator.spent(rootCategoryID: c.id, records, in: month, index: index))
            let state = p.state == .exceeded ? 2 : (p.state == .warning ? 1 : 0)
            return WatchSnapshot.Budget(id: b.id, name: c.name, icon: c.icon, colorKey: c.colorKey, spent: money.string(p.spent),
                                        limit: money.string(p.limit), ratio: p.ratio, state: state)
        }
        .sorted { $0.ratio > $1.ratio }

        let recent: [WatchSnapshot.Tx] = live.sorted { $0.date > $1.date }.prefix(8).map { t in
            let amount: String
            switch t.kind {
            case .income: amount = money.string(t.amount, signed: true)
            case .expense: amount = money.string(-t.amount)
            case .transfer: amount = money.string(t.amount)
            }
            return WatchSnapshot.Tx(id: t.id, title: t.displayTitle, subtitle: t.displaySubtitle, amount: amount, kind: t.kind, date: t.date,
                                    icon: t.kind == .transfer ? "arrow.left.arrow.right" : (t.category?.icon ?? "questionmark"),
                                    colorKey: t.category?.colorKey ?? "stone")
        }

        let balance = BalanceCalculator.total(balances)
        let f = OverviewMetrics.forecast(balance: balance, records: records, rules: rules, now: now)

        return WatchSnapshot(
            generatedAt: now,
            monthTitle: month.title(),
            totalBalance: money.string(balance),
            monthIncome: money.string(AnalyticsEngine.total(records, kind: .income, in: month)),
            monthExpense: money.string(AnalyticsEngine.total(records, kind: .expense, in: month)),
            forecast: money.string(f.projectedBalance),
            forecastNote: LF("В среднем %@ в день", money.string(f.averageDailySpending)),
            accounts: active.map { WatchSnapshot.Account(id: $0.id, name: $0.name, balance: money.string(balances[$0.id] ?? 0)) },
            budgets: Array(budgetRows.prefix(6)),
            recent: recent,
            expenseCategories: options(.expense, categories: categories, transactions: live),
            incomeCategories: options(.income, categories: categories, transactions: live))
    }

    /// Categories for quick entry: recently used first, then the rest in their usual order.
    private static func options(_ kind: CategoryKind, categories: [Category], transactions: [Transaction]) -> [WatchSnapshot.Category] {
        let all = categories.filter { $0.kind == kind && !$0.isArchived }
        var seen = Set<UUID>(), recent: [Category] = []
        for t in transactions.sorted(by: { $0.date > $1.date }) where t.kind == kind.txKind {
            if let c = t.category, !c.isArchived, seen.insert(c.id).inserted { recent.append(c) }
            if recent.count >= 6 { break }
        }
        func order(_ c: Category) -> (Int, Int, Int) { (c.parent?.sortOrder ?? c.sortOrder, c.parent == nil ? 0 : 1, c.sortOrder) }
        let rest = all.filter { !seen.contains($0.id) }.sorted { order($0) < order($1) }
        return (recent + rest).prefix(30).map { WatchSnapshot.Category(id: $0.id, name: $0.fullName, icon: $0.icon, colorKey: $0.colorKey) }
    }
}
