import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum ExportRange: String, CaseIterable, Identifiable {
    case all, month, year, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: L("Всё время")
        case .month: L("Этот месяц")
        case .year: L("Этот год")
        case .custom: L("Свой период")
        }
    }
}

struct ExportView: View {
    @Query(sort: \Transaction.date) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @State private var range = ExportRange.month
    @State private var from = Calendar.app.dateInterval(of: .month, for: Date())!.start
    @State private var to = Date()
    @State private var share: ShareItem?
    @State private var error: String?

    private var selected: [Transaction] {
        switch range {
        case .all: return transactions
        case .month: let p = Period.containing(Date(), kind: .month); return transactions.filter { p.contains($0.date) }
        case .year: let p = Period.containing(Date(), kind: .year); return transactions.filter { p.contains($0.date) }
        case .custom: let p = Period.custom(from: from, to: to); return transactions.filter { p.contains($0.date) }
        }
    }

    var body: some View {
        Form {
            Section("Период") {
                Picker("Период", selection: $range) { ForEach(ExportRange.allCases) { Text($0.title).tag($0) } }
                if range == .custom {
                    DatePicker("С", selection: $from, displayedComponents: .date)
                    DatePicker("По", selection: $to, displayedComponents: .date)
                }
            }.listRowBackground(Theme.Colors.card)
            Section {
                Text(LF("Операций к экспорту: %d", selected.count))
                Button("Экспортировать в .xlsx", action: export).disabled(selected.isEmpty)
            } footer: {
                Text("Файл откроется в Excel, Numbers и Google Таблицах. Расходы записываются со знаком минус.")
            }.listRowBackground(Theme.Colors.card)
            if let error { Text(error).foregroundStyle(Theme.Colors.expense) }
        }
        .scrollContentBackground(.hidden).background(Theme.Colors.background)
        .navigationTitle("Экспорт")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { ShareSheet(url: $0.url) }
    }

    private func export() {
        do {
            share = ShareItem(url: try TransactionExporter.write(transactions: selected, fileName: "Koshelek-\(FileStamp.string("yyyy-MM-dd")).xlsx"))
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var share: ShareItem?
    @State private var importing = false
    @State private var pending: BackupFile?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button("Создать резервную копию", action: backup)
            } header: { Text("Копия") } footer: {
                Text("JSON-файл со всеми счетами, категориями, операциями, регулярными платежами, бюджетами, целями и настройками.")
            }.listRowBackground(Theme.Colors.card)
            Section {
                Button("Восстановить из файла") { importing = true }
            } footer: { Text("Текущие данные будут заменены данными из файла. Перед заменой приложение попросит подтверждение.") }.listRowBackground(Theme.Colors.card)
            if let message { Section { Text(message).foregroundStyle(Theme.Colors.expense) }.listRowBackground(Theme.Colors.card) }
        }
        .scrollContentBackground(.hidden).background(Theme.Colors.background)
        .navigationTitle("Резервная копия")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                pending = try BackupService.validate(try Data(contentsOf: url))
                message = nil
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Заменить все данные?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Заменить данные", role: .destructive) {
                guard let file = pending else { return }
                pending = nil
                DataReplacement.run(settings: settings) {
                    do { try BackupService.restoreSafely(file, in: context, settings: settings) }
                    catch { AppErrors.shared.report(LF("Не удалось восстановить данные, прежние данные сохранены: %@", error.localizedDescription)) }
                }
            }
        } message: {
            if let p = pending {
                Text(LF("В копии: счетов %d, операций %d. Текущие данные будут удалены.", p.accounts.count, p.transactions.count))
            }
        }
    }

    private func backup() {
        do {
            let data = try BackupService.makeBackup(in: context, settings: settings)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Koshelek-backup-\(FileStamp.string("yyyy-MM-dd")).json")
            try data.write(to: url, options: .atomic)
            share = ShareItem(url: url)
            message = nil
        } catch { message = error.localizedDescription }
    }
}
