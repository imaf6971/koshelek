#if DEBUG
import Foundation

extension WatchSnapshot {
    /// Realistic sample data for checking the watch screens without a paired phone (launch argument -sampleSnapshot).
    static var sample: WatchSnapshot {
        func cat(_ name: String, _ icon: String, _ color: String) -> Category { Category(id: UUID(), name: name, icon: icon, colorKey: color) }
        return WatchSnapshot(
            generatedAt: Date(), monthTitle: "Октябрь 2026 г.", totalBalance: "685\u{00A0}036\u{00A0}₽",
            monthIncome: "179\u{00A0}500\u{00A0}₽", monthExpense: "82\u{00A0}669\u{00A0}₽",
            forecast: "651\u{00A0}217\u{00A0}₽", forecastNote: "В среднем 3\u{00A0}758\u{00A0}₽ в день",
            accounts: [Account(id: UUID(), name: "Карта", balance: "402\u{00A0}966\u{00A0}₽"),
                       Account(id: UUID(), name: "Наличные", balance: "12\u{00A0}070\u{00A0}₽"),
                       Account(id: UUID(), name: "Накопления", balance: "270\u{00A0}000\u{00A0}₽")],
            budgets: [
                Budget(id: UUID(), name: "Развлечения", icon: "film", colorKey: "ochre", spent: "5\u{00A0}109\u{00A0}₽", limit: "6\u{00A0}000\u{00A0}₽", ratio: 0.85, state: 1),
                Budget(id: UUID(), name: "Еда", icon: "fork.knife", colorKey: "clay", spent: "41\u{00A0}000\u{00A0}₽", limit: "38\u{00A0}000\u{00A0}₽", ratio: 1.08, state: 2),
                Budget(id: UUID(), name: "Транспорт", icon: "bus", colorKey: "slate", spent: "3\u{00A0}950\u{00A0}₽", limit: "9\u{00A0}000\u{00A0}₽", ratio: 0.44, state: 0)],
            recent: [
                Tx(id: UUID(), title: "Здоровье", subtitle: "Карта", amount: "−3\u{00A0}050\u{00A0}₽", kind: .expense, date: Date(), icon: "cross.case", colorKey: "rose"),
                Tx(id: UUID(), title: "Еда → Продукты", subtitle: "Карта", amount: "−3\u{00A0}420\u{00A0}₽", kind: .expense, date: Date(), icon: "cart", colorKey: "clay"),
                Tx(id: UUID(), title: "Зарплата", subtitle: "Карта", amount: "+56\u{00A0}000\u{00A0}₽", kind: .income, date: Date(), icon: "banknote", colorKey: "moss")],
            expenseCategories: [cat("Еда → Продукты", "cart", "clay"), cat("Транспорт → Такси", "car", "slate"), cat("Здоровье", "cross.case", "rose"), cat("Прочее", "ellipsis.circle", "stone")],
            incomeCategories: [cat("Зарплата", "banknote", "moss"), cat("Подработка", "briefcase", "olive")])
    }
}
#endif
