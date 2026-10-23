import Foundation

/// Value copies of what a list row shows. Rows built from these never touch SwiftData objects, so a row that is still
/// on screen while its object is being deleted cannot crash. Actions look the object up again by `id` when they run.
struct TxRowData: Identifiable, Equatable {
    var id: UUID
    var title: String
    var subtitle: String
    var amountText: String
    var kind: TxKind
    var icon: String
    var colorKey: String
}

struct BudgetRowData: Identifiable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var colorKey: String
    var progress: BudgetProgress
}

extension Transaction {
    func rowData(_ money: MoneyFormatter) -> TxRowData {
        let amount: String
        switch kind {
        case .income: amount = money.string(self.amount, signed: true)
        case .expense: amount = money.string(-self.amount)
        case .transfer: amount = money.string(self.amount)
        }
        return TxRowData(id: id, title: displayTitle, subtitle: displaySubtitle, amountText: amount, kind: kind,
                         icon: kind == .transfer ? "arrow.left.arrow.right" : (category?.icon ?? "questionmark"),
                         colorKey: category?.colorKey ?? "stone")
    }
}

enum BudgetRows {
    /// Budget rows for the month, fullest first. Budgets whose category is gone are skipped.
    static func make(_ budgets: [Budget], records: [TxRecord], month: Period, index: CategoryIndex) -> [BudgetRowData] {
        budgets.compactMap { b in
            guard let c = b.category else { return nil }
            let p = BudgetEvaluator.progress(limit: b.monthlyLimit, spent: BudgetEvaluator.spent(rootCategoryID: c.id, records, in: month, index: index))
            return BudgetRowData(id: b.id, name: c.name, icon: c.icon, colorKey: c.colorKey, progress: p)
        }
        .sorted { $0.progress.ratio > $1.progress.ratio }
    }
}
