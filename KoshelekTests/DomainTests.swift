import XCTest
@testable import Koshelek

private let cal = Calendar.app
private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}
private func tx(_ kind: TxKind, _ amount: Decimal, _ d: Date, account: UUID? = nil, to: UUID? = nil, category: UUID? = nil,
                tags: [String] = [], note: String = "") -> TxRecord {
    TxRecord(id: UUID(), kind: kind, amount: amount, date: d, accountID: account, toAccountID: to, categoryID: category, tags: tags, note: note)
}

final class MoneyTests: XCTestCase {
    func testFormatsWithRussianConventions() {
        let f = MoneyFormatter(symbol: "₽")
        XCTAssertEqual(f.string(1234567), "1\u{00A0}234\u{00A0}567\u{00A0}₽")
        XCTAssertEqual(f.string(Decimal(string: "1234.5")!), "1\u{00A0}234,50\u{00A0}₽")
        XCTAssertEqual(f.string(-50), "−50\u{00A0}₽")
        XCTAssertEqual(f.string(10, signed: true), "+10\u{00A0}₽")
    }

    func testParser() {
        XCTAssertEqual(MoneyParser.parse("1 234,50"), Decimal(string: "1234.5"))
        XCTAssertEqual(MoneyParser.parse("99.9"), Decimal(string: "99.9"))
        XCTAssertNil(MoneyParser.parse(""))
        XCTAssertNil(MoneyParser.parse("1.2.3"))
    }

    func testDecimalHasNoBinaryError() {
        let sum = (0..<10).reduce(Decimal(0)) { acc, _ in acc + Decimal(string: "0.1")! }
        XCTAssertEqual(sum, 1)
    }
}

final class BalanceTests: XCTestCase {
    func testTransfersMoveMoneyWithoutChangingTotal() {
        let a = UUID(), b = UUID()
        let txs = [
            tx(.income, 1000, date(2026, 1, 1), account: a),
            tx(.expense, 200, date(2026, 1, 2), account: a),
            tx(.transfer, 300, date(2026, 1, 3), account: a, to: b),
        ]
        let r = BalanceCalculator.balances(initial: [a: 100, b: 50], transactions: txs)
        XCTAssertEqual(r[a], 600)
        XCTAssertEqual(r[b], 350)
        XCTAssertEqual(BalanceCalculator.total(r), 950)
    }
}

final class PeriodTests: XCTestCase {
    func testWeekStartsOnMonday() {
        let p = Period.containing(date(2026, 10, 22), kind: .week)   // Thursday
        XCTAssertEqual(cal.component(.weekday, from: p.start), 2)
        XCTAssertEqual(p.dayCount(), 7)
    }

    func testMonthAndPrevious() {
        let p = Period.containing(date(2026, 3, 15), kind: .month)
        XCTAssertEqual(p.dayCount(), 31)
        XCTAssertEqual(p.previous().dayCount(), 28)
        XCTAssertEqual(p.comparisonLabel(), "к февралю")
    }

    func testCustomPreviousHasSameLength() {
        let p = Period.custom(from: date(2026, 5, 10), to: date(2026, 5, 19))
        XCTAssertEqual(p.dayCount(), 10)
        XCTAssertEqual(p.previous().dayCount(), 10)
        XCTAssertEqual(p.previous().end, p.start)
    }
}

final class AnalyticsTests: XCTestCase {
    let food = UUID(), cafe = UUID(), shops = UUID(), taxi = UUID(), salary = UUID()
    var index: CategoryIndex {
        CategoryIndex([
            CategoryInfo(id: food, name: "Еда", parentID: nil, kind: .expense),
            CategoryInfo(id: cafe, name: "Кафе", parentID: food, kind: .expense),
            CategoryInfo(id: shops, name: "Продукты", parentID: food, kind: .expense),
            CategoryInfo(id: taxi, name: "Такси", parentID: nil, kind: .expense),
            CategoryInfo(id: salary, name: "Зарплата", parentID: nil, kind: .income),
        ])
    }
    let october = Period.containing(date(2026, 10, 10), kind: .month)
    let september = Period.containing(date(2026, 9, 10), kind: .month)

    func testBreakdownRollsSubcategoriesUpAndIgnoresTransfersAndIncome() {
        let a = UUID(), b = UUID()
        let txs = [
            tx(.expense, 300, date(2026, 10, 2), category: cafe),
            tx(.expense, 700, date(2026, 10, 3), category: shops),
            tx(.expense, 500, date(2026, 10, 4), category: taxi),
            tx(.income, 90_000, date(2026, 10, 1), category: salary),
            tx(.transfer, 5_000, date(2026, 10, 5), account: a, to: b),
            tx(.expense, 999, date(2026, 9, 5), category: taxi),
        ]
        let s = AnalyticsEngine.breakdown(txs, in: october, index: index)
        XCTAssertEqual(s.map(\.id), [food, taxi])
        XCTAssertEqual(s[0].amount, 1000)
        XCTAssertEqual(s[0].share, 1000.0 / 1500.0, accuracy: 1e-9)
        XCTAssertEqual(AnalyticsEngine.total(txs, kind: .expense, in: october), 1500)
        XCTAssertEqual(AnalyticsEngine.total(txs, kind: .income, in: october), 90_000)
        let sub = AnalyticsEngine.subBreakdown(txs, in: october, rootID: food, index: index)
        XCTAssertEqual(sub.map(\.id), [shops, cafe])
    }

    func testComparison() {
        let txs = [
            tx(.expense, 123, date(2026, 10, 2), category: cafe),
            tx(.expense, 100, date(2026, 9, 2), category: cafe),
            tx(.expense, 50, date(2026, 10, 2), category: taxi),
        ]
        let d = AnalyticsEngine.comparison(txs, current: october, previous: september, index: index)
        let food = d.first { $0.id == self.food }!
        XCTAssertEqual(food.change!, 0.23, accuracy: 1e-9)
        XCTAssertNil(d.first { $0.id == taxi }!.change)
    }

    func testMonthlySeriesAndTop() {
        let txs = [
            tx(.income, 100, date(2026, 9, 1)), tx(.expense, 40, date(2026, 9, 2)),
            tx(.expense, 70, date(2026, 10, 2)), tx(.expense, 10, date(2026, 10, 3)),
        ]
        let m = AnalyticsEngine.monthly(txs, from: date(2026, 9, 1), count: 2)
        XCTAssertEqual(m.map(\.income), [100, 0])
        XCTAssertEqual(m.map(\.expense), [40, 80])
        XCTAssertEqual(AnalyticsEngine.topExpenses(txs, in: october, limit: 1).first?.amount, 70)
    }
}

final class PlanningTests: XCTestCase {
    func testBudgetStates() {
        XCTAssertEqual(BudgetEvaluator.progress(limit: 100, spent: 79).state, .normal)
        XCTAssertEqual(BudgetEvaluator.progress(limit: 100, spent: 80).state, .warning)
        XCTAssertEqual(BudgetEvaluator.progress(limit: 100, spent: 100).state, .warning)
        XCTAssertEqual(BudgetEvaluator.progress(limit: 100, spent: 101).state, .exceeded)
        XCTAssertTrue(BudgetEvaluator.crossedLimit(before: 90, after: 120, limit: 100))
        XCTAssertFalse(BudgetEvaluator.crossedLimit(before: 110, after: 120, limit: 100))
    }

    func testBudgetSpentIncludesSubcategories() {
        let food = UUID(), cafe = UUID()
        let index = CategoryIndex([CategoryInfo(id: food, name: "Еда", parentID: nil, kind: .expense),
                                   CategoryInfo(id: cafe, name: "Кафе", parentID: food, kind: .expense)])
        let txs = [tx(.expense, 10, date(2026, 10, 1), category: food), tx(.expense, 5, date(2026, 10, 2), category: cafe),
                   tx(.expense, 99, date(2026, 11, 2), category: cafe)]
        let spent = BudgetEvaluator.spent(rootCategoryID: food, txs, in: .containing(date(2026, 10, 5), kind: .month), index: index)
        XCTAssertEqual(spent, 15)
    }

    func testForecast() {
        // Oct 10: 10 days elapsed, 21 remaining; 5000 spent -> 500/day
        let f = ForecastEngine.forecast(currentBalance: 100_000, monthExpenseSoFar: 5_000, today: date(2026, 10, 10), scheduledNet: -2_000)
        XCTAssertEqual(f.averageDailySpending, 500)
        XCTAssertEqual(f.remainingDays, 21)
        XCTAssertEqual(f.projectedBalance, 100_000 - 500 * 21 - 2_000)
    }

    func testMonthlyRecurrenceClampsToMonthEnd() {
        let rule = RuleSchedule(frequency: .monthly, startDate: date(2026, 1, 31), endDate: nil)
        let o = RecurrenceGenerator.occurrences(rule, through: date(2026, 4, 30, 23))
        XCTAssertEqual(o.map { cal.component(.day, from: $0) }, [31, 28, 31, 30])
    }

    func testRecurrenceEndDateAndDuplicates() {
        let rule = RuleSchedule(frequency: .weekly, startDate: date(2026, 10, 1), endDate: date(2026, 10, 15))
        let all = RecurrenceGenerator.occurrences(rule, through: date(2026, 12, 1))
        XCTAssertEqual(all.count, 3)   // 1, 8, 15
        let existing: Set<Date> = [all[0]]
        let due = RecurrenceGenerator.due(rule, lastGenerated: nil, existing: existing, now: date(2026, 12, 1))
        XCTAssertEqual(due, Array(all.dropFirst()))
        XCTAssertTrue(RecurrenceGenerator.due(rule, lastGenerated: all[2], existing: [], now: date(2026, 12, 1)).isEmpty)
    }

    func testFilter() {
        let food = UUID(), cafe = UUID(), a = UUID(), b = UUID()
        let index = CategoryIndex([CategoryInfo(id: food, name: "Еда", parentID: nil, kind: .expense),
                                   CategoryInfo(id: cafe, name: "Кафе", parentID: food, kind: .expense)])
        let t1 = tx(.expense, 100, date(2026, 10, 1), account: a, category: cafe, tags: ["работа"], note: "Обед с коллегами")
        let t2 = tx(.expense, 900, date(2026, 10, 20), account: b, category: nil, note: "Подарок")
        let all = [t1, t2]
        var f = TransactionFilter()
        XCTAssertEqual(f.apply(all, index: index).count, 2)
        f.categoryIDs = [food]
        XCTAssertEqual(f.apply(all, index: index), [t1])
        f = TransactionFilter(); f.minAmount = 500
        XCTAssertEqual(f.apply(all, index: index), [t2])
        f = TransactionFilter(); f.to = date(2026, 10, 1, 8)
        XCTAssertEqual(f.apply(all, index: index), [t1])
        f = TransactionFilter(); f.text = "ОБЕД"
        XCTAssertEqual(f.apply(all, index: index), [t1])
        f = TransactionFilter(); f.tags = ["работа"]; f.accountIDs = [a]
        XCTAssertEqual(f.apply(all, index: index), [t1])
    }
}

final class SanitizeTests: XCTestCase {
    func testSanitizeAmountInput() {
        XCTAssertEqual(MoneyParser.sanitize("1250б5"), "12505")
        XCTAssertEqual(MoneyParser.sanitize("12.50"), "12,50")
        XCTAssertEqual(MoneyParser.sanitize("1,2,3"), "1,23")
        XCTAssertEqual(MoneyParser.sanitize("5,123"), "5,12")
        XCTAssertEqual(MoneyParser.sanitize("abc"), "")
        XCTAssertEqual(MoneyParser.sanitize("12345678901234"), "1234567890", "absurdly long amounts are cut off")
        XCTAssertEqual(MoneyParser.sanitize("12345678901234,567"), "1234567890,56")
    }
}
