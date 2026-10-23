import Foundation

enum BudgetState { case normal, warning, exceeded }

struct BudgetProgress: Equatable {
    var limit: Decimal
    var spent: Decimal
    var ratio: Double { limit == 0 ? 0 : (spent / limit).doubleValue }
    var remaining: Decimal { limit - spent }
    var state: BudgetState {
        if ratio > 1 { return .exceeded }
        if ratio >= 0.8 { return .warning }
        return .normal
    }
}

enum BudgetEvaluator {
    /// Expenses of a top-level category (including subcategories) within the period.
    static func spent(rootCategoryID: UUID, _ txs: [TxRecord], in period: Period, index: CategoryIndex) -> Decimal {
        let family = index.family(of: rootCategoryID)
        return txs.reduce(0) { sum, t in
            t.kind == .expense && period.contains(t.date) && t.categoryID.map(family.contains) == true ? sum + t.amount : sum
        }
    }

    static func progress(limit: Decimal, spent: Decimal) -> BudgetProgress { BudgetProgress(limit: limit, spent: spent) }

    /// True when a new expense pushes spending over the limit for the first time.
    static func crossedLimit(before: Decimal, after: Decimal, limit: Decimal) -> Bool {
        limit > 0 && before <= limit && after > limit
    }
}

struct Forecast: Equatable {
    var projectedBalance: Decimal
    var averageDailySpending: Decimal
    var remainingDays: Int
    /// Net effect of recurring transactions still due this month (income positive, expenses negative).
    var scheduledNet: Decimal
}

enum ForecastEngine {
    static func forecast(currentBalance: Decimal, monthExpenseSoFar: Decimal, today: Date, scheduledNet: Decimal, calendar: Calendar = .app) -> Forecast {
        let day = calendar.component(.day, from: today)
        let daysInMonth = calendar.range(of: .day, in: .month, for: today)!.count
        let remaining = max(daysInMonth - day, 0)
        let avg = monthExpenseSoFar / Decimal(max(day, 1))
        let projected = currentBalance - avg * Decimal(remaining) + scheduledNet
        return Forecast(projectedBalance: projected.rounded(0), averageDailySpending: avg.rounded(0), remainingDays: remaining, scheduledNet: scheduledNet)
    }
}

struct RuleSchedule {
    var frequency: Frequency
    var startDate: Date
    var endDate: Date?
}

enum RecurrenceGenerator {
    /// All occurrence days of a schedule up to and including `through`.
    static func occurrences(_ rule: RuleSchedule, through: Date, calendar: Calendar = .app, limit: Int = 5000) -> [Date] {
        let start = calendar.startOfDay(for: rule.startDate)
        let last = min(through, rule.endDate.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))!.addingTimeInterval(-1) } ?? through)
        var result: [Date] = []
        var n = 0
        while n < limit, let d = calendar.date(byAdding: rule.frequency.calendarComponent, value: n, to: start), d <= last {
            result.append(d)
            n += 1
        }
        return result
    }

    /// Occurrences that still need to be created: after the last generated day and not already present.
    static func due(_ rule: RuleSchedule, lastGenerated: Date?, existing: Set<Date>, now: Date, calendar: Calendar = .app) -> [Date] {
        occurrences(rule, through: now, calendar: calendar).filter { d in
            if let lg = lastGenerated, d <= lg { return false }
            return !existing.contains(d)
        }
    }

    /// Occurrences strictly after `now` and up to `until`.
    static func upcoming(_ rule: RuleSchedule, after now: Date, until: Date, calendar: Calendar = .app) -> [Date] {
        occurrences(rule, through: until, calendar: calendar).filter { $0 > now }
    }
}

struct TransactionFilter: Equatable {
    var from: Date?
    var to: Date?           // inclusive day
    var minAmount: Decimal?
    var maxAmount: Decimal?
    var categoryIDs: Set<UUID> = []
    var accountIDs: Set<UUID> = []
    var tags: Set<String> = []
    var text: String = ""

    var isActive: Bool { self != TransactionFilter() }
    /// Number of active criteria, excluding free text (shown in the search field).
    var activeCount: Int {
        [from != nil || to != nil, minAmount != nil || maxAmount != nil, !categoryIDs.isEmpty, !accountIDs.isEmpty, !tags.isEmpty].filter { $0 }.count
    }

    func apply(_ txs: [TxRecord], index: CategoryIndex, calendar: Calendar = .app) -> [TxRecord] {
        var categories = Set<UUID>()
        for id in categoryIDs { categories.formUnion(index.family(of: id)) }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let end = to.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))! }
        let start = from.map { calendar.startOfDay(for: $0) }
        return txs.filter { t in
            if let start, t.date < start { return false }
            if let end, t.date >= end { return false }
            if let minAmount, t.amount < minAmount { return false }
            if let maxAmount, t.amount > maxAmount { return false }
            if !categories.isEmpty, !(t.categoryID.map(categories.contains) ?? false) { return false }
            if !accountIDs.isEmpty {
                let ids = [t.accountID, t.toAccountID].compactMap { $0 }
                if !ids.contains(where: accountIDs.contains) { return false }
            }
            if !tags.isEmpty, tags.isDisjoint(with: t.tags) { return false }
            if !query.isEmpty {
                let hay = (t.note + " " + t.tags.joined(separator: " ") + " " + index.name(of: t.categoryID)).lowercased()
                if !hay.contains(query) { return false }
            }
            return true
        }
    }
}
