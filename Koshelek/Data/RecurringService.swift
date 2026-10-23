import Foundation
import SwiftData

enum RecurringService {
    /// Creates all due occurrences of active rules. Safe to call repeatedly: occurrences are never duplicated.
    @discardableResult
    static func generateDue(in context: ModelContext, now: Date = Date(), calendar: Calendar = .app) -> Int {
        guard let rules = try? context.fetch(FetchDescriptor<RecurringRule>()) else { return 0 }
        let generated = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.ruleID != nil }))) ?? []
        var existing: [UUID: Set<Date>] = [:]
        for t in generated {
            if let id = t.ruleID, let d = t.occurrenceDate { existing[id, default: []].insert(calendar.startOfDay(for: d)) }
        }
        var created = 0
        for rule in rules where rule.isActive && rule.account != nil {
            let dates = RecurrenceGenerator.due(rule.schedule, lastGenerated: rule.lastGeneratedDate, existing: existing[rule.id] ?? [], now: now, calendar: calendar)
            for d in dates {
                context.insert(Transaction(kind: rule.kind, amount: rule.amount, date: d, note: rule.note, account: rule.account,
                                           category: rule.category, ruleID: rule.id, occurrenceDate: d))
                created += 1
            }
            if let last = dates.last { rule.lastGeneratedDate = last }
        }
        if created > 0 || context.hasChanges { context.saveOrReport() }
        return created
    }
}
