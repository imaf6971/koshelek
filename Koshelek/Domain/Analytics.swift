import Foundation

struct CategorySlice: Identifiable, Hashable {
    /// Top-level category id (nil for uncategorized).
    var id: UUID?
    var amount: Decimal
    var share: Double
}

struct MonthPoint: Identifiable, Hashable {
    var month: Date
    var income: Decimal
    var expense: Decimal
    var id: Date { month }
}

struct CategoryDelta: Identifiable, Hashable {
    var id: UUID?
    var current: Decimal
    var previous: Decimal
    /// Fractional change versus previous; nil when there was nothing before.
    var change: Double? {
        previous == 0 ? nil : ((current - previous) / previous).doubleValue
    }
}

enum AnalyticsEngine {
    /// Income or expense records in the period. Transfers are never included.
    static func records(_ txs: [TxRecord], kind: TxKind, in period: Period) -> [TxRecord] {
        guard kind != .transfer else { return [] }
        return txs.filter { $0.kind == kind && period.contains($0.date) }
    }

    static func total(_ txs: [TxRecord], kind: TxKind, in period: Period) -> Decimal {
        records(txs, kind: kind, in: period).reduce(0) { $0 + $1.amount }
    }

    /// Spending grouped by top-level category, largest first.
    static func breakdown(_ txs: [TxRecord], kind: TxKind = .expense, in period: Period, index: CategoryIndex) -> [CategorySlice] {
        var sums: [UUID?: Decimal] = [:]
        for t in records(txs, kind: kind, in: period) {
            sums[index.rootID(of: t.categoryID), default: 0] += t.amount
        }
        return slices(from: sums)
    }

    /// Breakdown of one top-level category by its subcategories. The root itself represents entries without a subcategory.
    static func subBreakdown(_ txs: [TxRecord], kind: TxKind = .expense, in period: Period, rootID: UUID?, index: CategoryIndex) -> [CategorySlice] {
        var sums: [UUID?: Decimal] = [:]
        for t in records(txs, kind: kind, in: period) where index.rootID(of: t.categoryID) == rootID {
            sums[t.categoryID, default: 0] += t.amount
        }
        return slices(from: sums)
    }

    private static func slices(from sums: [UUID?: Decimal]) -> [CategorySlice] {
        let total = sums.values.reduce(0, +)
        return sums
            .map { CategorySlice(id: $0.key, amount: $0.value, share: total == 0 ? 0 : ($0.value / total).doubleValue) }
            .sorted { $0.amount != $1.amount ? $0.amount > $1.amount : ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
    }

    /// Income and expense for `count` consecutive months starting at `firstMonth`.
    static func monthly(_ txs: [TxRecord], from firstMonth: Date, count: Int, calendar: Calendar = .app) -> [MonthPoint] {
        let start = calendar.dateInterval(of: .month, for: firstMonth)!.start
        return (0..<count).map { i in
            let s = calendar.date(byAdding: .month, value: i, to: start)!
            let p = Period.containing(s, kind: .month, calendar: calendar)
            return MonthPoint(month: s, income: total(txs, kind: .income, in: p), expense: total(txs, kind: .expense, in: p))
        }
    }

    static func comparison(_ txs: [TxRecord], kind: TxKind = .expense, current: Period, previous: Period, index: CategoryIndex) -> [CategoryDelta] {
        let cur = Dictionary(breakdown(txs, kind: kind, in: current, index: index).map { ($0.id, $0.amount) }, uniquingKeysWith: { a, _ in a })
        let prev = Dictionary(breakdown(txs, kind: kind, in: previous, index: index).map { ($0.id, $0.amount) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(cur.keys).union(prev.keys)
        return keys.map { CategoryDelta(id: $0, current: cur[$0] ?? 0, previous: prev[$0] ?? 0) }
            .sorted { abs(($0.current - $0.previous).doubleValue) > abs(($1.current - $1.previous).doubleValue) }
    }

    static func percentChange(current: Decimal, previous: Decimal) -> Double? {
        previous == 0 ? nil : ((current - previous) / previous).doubleValue
    }

    static func topExpenses(_ txs: [TxRecord], in period: Period, limit: Int) -> [TxRecord] {
        Array(records(txs, kind: .expense, in: period).sorted { $0.amount > $1.amount }.prefix(limit))
    }
}
