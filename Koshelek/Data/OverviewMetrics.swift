import Foundation

/// Numbers shown on the overview, shared by the phone screen and the watch snapshot.
enum OverviewMetrics {
    static func forecast(balance: Decimal, records: [TxRecord], rules: [RecurringRule], now: Date = Date(), calendar: Calendar = .app) -> Forecast {
        let month = Period.containing(now, kind: .month, calendar: calendar)
        var net: Decimal = 0
        // Same rules that RecurringService actually turns into transactions.
        for r in rules where r.modelContext != nil && r.isActive && r.kind != .transfer && r.account != nil {
            let n = RecurrenceGenerator.upcoming(r.schedule, after: now, until: month.lastDay, calendar: calendar).count
            net += (r.kind == .income ? r.amount : -r.amount) * Decimal(n)
        }
        let spent = AnalyticsEngine.total(records, kind: .expense, in: Period(kind: .month, start: month.start, end: min(month.end, now)))
        return ForecastEngine.forecast(currentBalance: balance, monthExpenseSoFar: spent, today: now, scheduledNet: net, calendar: calendar)
    }
}
