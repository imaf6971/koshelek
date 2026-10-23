import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @Query private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @State private var editing: ItemID?
    @State private var adding = false
    @State private var deleting: ItemID?

    private struct AccountRow: Identifiable { var id: UUID; var name: String; var icon: String; var colorKey: String; var balance: String; var isArchived: Bool }

    private var balances: [UUID: Decimal] {
        BalanceCalculator.balances(initial: Dictionary(accounts.map { ($0.id, $0.initialBalance) }, uniquingKeysWith: { a, _ in a }), transactions: transactions.records)
    }

    private var rows: [AccountRow] {
        let b = balances
        return accounts.map { AccountRow(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey, balance: settings.money.string(b[$0.id] ?? 0), isArchived: $0.isArchived) }
    }

    private func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }

    var body: some View {
        let all = rows
        List {
            Section {
                ForEach(all.filter { !$0.isArchived }) { row in rowView(row) }
                    .onMove { from, to in
                        var list = accounts.filter { !$0.isArchived }
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, a) in list.enumerated() { a.sortOrder = i }
                        context.saveOrReport()
                    }
            }.listRowBackground(Theme.Colors.card)
            if all.contains(where: \.isArchived) {
                Section("Архив") { ForEach(all.filter(\.isArchived)) { row in rowView(row) } }.listRowBackground(Theme.Colors.card)
            }
        }
        .listStyleWarm()
        .navigationTitle("Счета")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(Text("Добавить счёт")) }
        }
        .sheet(isPresented: $adding) { AccountEditView(account: nil) }
        .sheet(item: $editing) { item in
            if let a = account(item.id) { AccountEditView(account: a) }
        }
        .sheet(item: $deleting) { item in
            if let a = account(item.id) {
                DeleteReassignSheet(
                    title: LF("Удалить счёт «%@»?", a.name),
                    message: L("У счёта есть операции. Перенесите их на другой счёт или удалите вместе со счётом."),
                    targets: accounts.filter { $0.id != a.id && !$0.isArchived }.map { ($0.id, $0.name) },
                    allowNoTarget: false,
                    onMove: { id in Store.deleteAccount(a, moveTransactionsTo: accounts.first { $0.id == id }, in: context) },
                    onDeleteAll: { Store.deleteAccount(a, moveTransactionsTo: nil, in: context) })
            }
        }
    }

    private func rowView(_ row: AccountRow) -> some View {
        Button { editing = ItemID(id: row.id) } label: {
            AdaptiveRow {
                HStack(spacing: Theme.Spacing.m) { IconBadge(icon: row.icon, colorKey: row.colorKey); Text(row.name).foregroundStyle(Theme.Colors.textPrimary) }
            } trailing: {
                Text(row.balance).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .listRowBackground(Theme.Colors.card)
        .swipeActions(edge: .trailing) {
            Button("Удалить") { if let a = account(row.id) { requestDelete(a) } }.tint(Theme.Colors.expense)
            Button(row.isArchived ? "Вернуть" : "В архив") {
                if let a = account(row.id) { a.isArchived.toggle(); context.saveOrReport() }
            }.tint(Theme.Colors.textSecondary)
        }
    }

    private func requestDelete(_ a: Account) {
        if a.transactions.isEmpty && a.incomingTransfers.isEmpty {
            Store.deleteAccount(a, moveTransactionsTo: nil, in: context)
        } else {
            deleting = ItemID(id: a.id)
        }
    }
}

struct AccountEditView: View {
    let account: Account?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @State private var name = ""
    @State private var balanceText = ""
    @State private var icon = "creditcard"
    @State private var colorKey = "slate"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    TextField("Начальный баланс", text: $balanceText).keyboardType(.numbersAndPunctuation)
                }.listRowBackground(Theme.Colors.card)
                Section("Значок и цвет") { IconColorPicker(icon: $icon, colorKey: $colorKey) }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(account == nil ? "Новый счёт" : "Счёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard let a = account else { return }
                name = a.name; icon = a.icon; colorKey = a.colorKey
                balanceText = NSDecimalNumber(decimal: a.initialBalance).stringValue.replacingOccurrences(of: ".", with: ",")
            }
        }
    }

    private func save() {
        let balance = MoneyParser.parse(balanceText.replacingOccurrences(of: "-", with: "")) .map { balanceText.contains("-") ? -$0 : $0 } ?? 0
        let n = name.trimmingCharacters(in: .whitespaces)
        if let a = account {
            a.name = n; a.icon = icon; a.colorKey = colorKey; a.initialBalance = balance
        } else {
            context.insert(Account(name: n, icon: icon, colorKey: colorKey, initialBalance: balance, sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1))
        }
        context.saveOrReport()
        dismiss()
    }
}

/// Asks what to do with transactions before deleting a container (account or category).
struct DeleteReassignSheet: View {
    let title: String
    let message: String
    let targets: [(id: UUID, name: String)]
    let allowNoTarget: Bool
    let onMove: (UUID?) -> Void
    let onDeleteAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var target: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(message).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }.listRowBackground(Theme.Colors.card)
                Section("Перенести операции") {
                    Picker("Куда", selection: $target) {
                        if allowNoTarget { Text("Без категории").tag(UUID?.none) }
                        ForEach(targets, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Перенести и удалить") {
                        let chosen = target
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onMove(chosen) }
                    }
                        .disabled(target == nil && !allowNoTarget)
                }.listRowBackground(Theme.Colors.card)
                Section {
                    Button("Удалить вместе с операциями", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onDeleteAll() }
                    }
                }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear { if target == nil, !allowNoTarget { target = targets.first?.id } }
        }
        .presentationDetents([.medium])
    }
}
