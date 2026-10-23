import Foundation

enum TransactionExporter {
    /// Builds the export worksheet. Expenses are negative, income positive; transfers keep their positive amount.
    static func sheet(transactions: [Transaction]) -> XLSXSheet {
        let sorted = transactions.sorted { $0.date < $1.date }
        let rows: [[XLSXCell]] = sorted.map { t in
            let signed: Decimal = t.kind == .expense ? -t.amount : t.amount
            let category = t.category
            return [
                .date(t.date),
                .text(t.kind.title),
                .text(category?.parent?.name ?? category?.name ?? ""),
                .text(category?.parent != nil ? category?.name ?? "" : ""),
                .text(t.account?.name ?? ""),
                .text(t.toAccount?.name ?? ""),
                .number(signed),
                .text(t.tags.joined(separator: ", ")),
                .text(t.note),
            ]
        }
        return XLSXSheet(
            name: L("Операции"),
            columns: [
                .init(title: L("Дата"), width: 12, style: .date),
                .init(title: L("Тип"), width: 11, style: .general),
                .init(title: L("Категория"), width: 22, style: .general),
                .init(title: L("Подкатегория"), width: 22, style: .general),
                .init(title: L("Счёт"), width: 18, style: .general),
                .init(title: L("Счёт зачисления"), width: 18, style: .general),
                .init(title: L("Сумма"), width: 14, style: .amount),
                .init(title: L("Теги"), width: 20, style: .general),
                .init(title: L("Заметка"), width: 36, style: .general),
            ],
            rows: rows)
    }

    static func write(transactions: [Transaction], fileName: String) throws -> URL {
        let data = XLSXWriter.data(for: sheet(transactions: transactions))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
