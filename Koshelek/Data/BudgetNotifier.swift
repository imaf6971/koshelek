import Foundation
import SwiftData
import UserNotifications

enum BudgetNotifier {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func notifyExceeded(categoryID: UUID, categoryName: String, spent: String, limit: String, monthKey: String) {
        let content = UNMutableNotificationContent()
        content.title = L("Бюджет превышен")
        content.body = LF("«%@»: потрачено %@ из %@", categoryName, spent, limit)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "budget-\(categoryID.uuidString)-\(monthKey)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}

extension BudgetNotifier {
    /// Posts a local notification if this expense pushed a monthly budget over its limit. Budgets can be set on a top-level
    /// category or on a subcategory, so both the expense's own category and its parent are checked.
    @MainActor
    static func checkExceeded(after t: Transaction, in context: ModelContext, settings: AppSettings) {
        guard settings.budgetNotifications, t.kind == .expense, let category = t.category else { return }
        let ids = Set([category.id] + [category.parent?.id].compactMap { $0 })
        let budgets = ((try? context.fetch(FetchDescriptor<Budget>())) ?? []).live.filter { $0.category.map { ids.contains($0.id) } ?? false }
        guard !budgets.isEmpty else { return }
        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let index = CategoryIndex(categories.live.map(\.info))
        let records = transactions.records
        let month = Period.containing(t.date, kind: .month)
        for budget in budgets {
            guard let c = budget.category else { continue }
            let after = BudgetEvaluator.spent(rootCategoryID: c.id, records, in: month, index: index)
            if BudgetEvaluator.crossedLimit(before: after - t.amount, after: after, limit: budget.monthlyLimit) {
                notifyExceeded(categoryID: c.id, categoryName: c.name, spent: settings.money.string(after),
                               limit: settings.money.string(budget.monthlyLimit), monthKey: "\(Int(month.start.timeIntervalSince1970))")
            }
        }
    }
}
