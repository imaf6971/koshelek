#if DEBUG
import Foundation
import SwiftData

/// Realistic Russian demo data for development. Compiled only into DEBUG builds.
enum DemoData {
    private struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static func seed(in context: ModelContext, now: Date = Date()) {
        Store.wipeAll(in: context)
        DefaultCategories.ensure(in: context)
        let cal = Calendar.app
        var rng = RNG(state: 42)

        let card = Account(name: "Карта", icon: "creditcard", colorKey: "slate", initialBalance: 45000, sortOrder: 0)
        let cash = Account(name: "Наличные", icon: "banknote", colorKey: "olive", initialBalance: 8000, sortOrder: 1)
        let savings = Account(name: "Накопления", icon: "building.columns", colorKey: "ochre", initialBalance: 150000, sortOrder: 2)
        [card, cash, savings].forEach(context.insert)

        let cats = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        func cat(_ name: String, _ kind: CategoryKind = .expense) -> Category? { cats.first { $0.name == name && $0.kind == kind } }

        func add(_ kind: TxKind, _ amount: Int, _ date: Date, _ category: Category?, _ account: Account, note: String = "", tags: [String] = [], to: Account? = nil) {
            guard date <= now else { return }
            context.insert(Transaction(kind: kind, amount: Decimal(amount), date: date, note: note, tags: tags, account: account, toAccount: to, category: category))
        }
        func day(_ monthOffset: Int, _ d: Int, hour: Int = 12) -> Date {
            let base = cal.date(byAdding: .month, value: monthOffset, to: cal.dateInterval(of: .month, for: now)!.start)!
            let maxDay = cal.range(of: .day, in: .month, for: base)!.count
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: min(d, maxDay) - 1, to: base)!)!
        }
        func r(_ range: ClosedRange<Int>, step: Int = 10) -> Int { Int.random(in: (range.lowerBound / step)...(range.upperBound / step), using: &rng) * step }

        let shops = ["Пятёрочка", "ВкусВилл", "Перекрёсток", "Магнит"]
        let cafes = ["Кофейня у дома", "Ресторан «Тоска»", "Шоколадница", "Обед в офисе"]
        for m in -5...0 {
            add(.income, 115_000 + r(0...15_000, step: 500), day(m, 1), cat("Зарплата", .income), card, note: "Зарплата")
            add(.income, 55_000 + r(0...12_000, step: 500), day(m, 16), cat("Зарплата", .income), card, note: "Аванс")
            if m % 2 == 0 { add(.income, r(8_000...25_000, step: 500), day(m, 22), cat("Подработка", .income), card, note: "Фриланс-проект", tags: ["работа"]) }
            add(.transfer, 20_000, day(m, 3), nil, card, note: "Откладываю", to: savings)
            add(.transfer, 7_000, day(m, 8), nil, card, note: "Снял наличные", to: cash)
            for _ in 0..<9 { add(.expense, r(500...4_200), day(m, Int.random(in: 1...28, using: &rng)), cat("Продукты"), card, note: shops.randomElement(using: &rng)!) }
            for _ in 0..<6 { add(.expense, r(350...2_800), day(m, Int.random(in: 1...28, using: &rng)), cat("Кафе и рестораны"), Bool.random(using: &rng) ? card : cash, note: cafes.randomElement(using: &rng)!, tags: ["кафе"]) }
            for _ in 0..<2 { add(.expense, r(600...1_800), day(m, Int.random(in: 1...28, using: &rng)), cat("Доставка еды"), card, note: "Яндекс Еда") }
            for _ in 0..<5 { add(.expense, r(250...1_100), day(m, Int.random(in: 1...28, using: &rng)), cat("Такси"), card, note: "Поездка") }
            add(.expense, r(1_500...3_500), day(m, 10), cat("Транспорт"), card, note: "Проездной")
            add(.expense, r(3_800...6_200), day(m, 14), cat("Коммунальные услуги"), card, note: "ЖКУ")
            add(.expense, r(1_500...9_000), day(m, Int.random(in: 5...25, using: &rng)), cat("Одежда"), card, note: "Покупки")
            add(.expense, r(1_000...6_000), day(m, Int.random(in: 5...25, using: &rng)), cat("Здоровье"), card, note: "Аптека / врач")
            add(.expense, r(1_200...5_000), day(m, Int.random(in: 5...25, using: &rng)), cat("Кино и театр"), card, note: "Билеты", tags: ["отдых"])
            add(.expense, r(1_000...7_000), day(m, Int.random(in: 5...25, using: &rng)), cat("Подарки"), card, note: "Подарок")
            add(.expense, r(800...2_500), day(m, Int.random(in: 5...25, using: &rng)), cat("Питомцы"), cash, note: "Корм")
            if m == -2 { add(.expense, 48_000, day(m, 12), cat("Путешествия"), card, note: "Билеты в Казань", tags: ["отпуск"]) }
        }

        let rent = RecurringRule(amount: 35_000, note: "Аренда квартиры", frequency: .monthly, startDate: day(-5, 5), account: card, category: cat("Аренда"))
        let streaming = RecurringRule(amount: 599, note: "Онлайн-кинотеатр", frequency: .monthly, startDate: day(-5, 12), account: card, category: cat("Подписки"))
        let internet = RecurringRule(amount: 750, note: "Домашний интернет", frequency: .monthly, startDate: day(-5, 20), account: card, category: cat("Интернет и связь"))
        [rent, streaming, internet].forEach(context.insert)

        for (name, limit) in [("Еда", 38_000), ("Транспорт", 9_000), ("Развлечения", 6_000), ("Одежда", 8_000), ("Здоровье", 5_000)] {
            if let c = cat(name) { context.insert(Budget(monthlyLimit: Decimal(limit), category: c)) }
        }

        let trip = SavingsGoal(name: "Отпуск на море", icon: "airplane", colorKey: "sage", targetAmount: 180_000, deadline: cal.date(byAdding: .month, value: 5, to: now))
        let reserve = SavingsGoal(name: "Подушка безопасности", icon: "heart", colorKey: "rose", targetAmount: 500_000)
        context.insert(trip); context.insert(reserve)
        for (i, v) in [15_000, 20_000, 12_000, 25_000].enumerated() { context.insert(GoalContribution(amount: Decimal(v), date: day(-3 + i, 18), goal: trip)) }
        for (i, v) in [60_000, 40_000].enumerated() { context.insert(GoalContribution(amount: Decimal(v), date: day(-2 + i, 4), goal: reserve)) }

        context.saveOrReport()
        RecurringService.generateDue(in: context, now: now)
    }
}
#endif
