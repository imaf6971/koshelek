import SwiftUI
import SwiftData

@Observable final class EntryViewModel {
    var kind: TxKind = .expense
    var amountText = ""
    var date = Date()
    var account: Account?
    var toAccount: Account?
    var category: Category?
    var tagsText = ""
    var note = ""

    var amount: Decimal? { MoneyParser.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }

    var tags: [String] {
        tagsText.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "#" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var canSave: Bool {
        guard amount != nil, account != nil else { return false }
        if kind == .transfer { return toAccount != nil && toAccount?.id != account?.id }
        return true
    }

    init(editing t: Transaction? = nil) {
        guard let t else { return }
        kind = t.kind; amountText = Self.plain(t.amount); date = t.date; account = t.account; toAccount = t.toAccount
        category = t.category; tagsText = t.tags.joined(separator: " "); note = t.note
    }

    private static func plain(_ d: Decimal) -> String {
        NSDecimalNumber(decimal: d).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    /// Writes the form into `tx` (or a new transaction) and returns it.
    func commit(into tx: Transaction?, context: ModelContext) -> Transaction? {
        guard canSave, let amount else { return nil }
        let t = tx ?? Transaction(kind: kind, amount: amount, date: date, account: account)
        t.kind = kind; t.amount = amount; t.date = date; t.account = account
        t.toAccount = kind == .transfer ? toAccount : nil
        t.category = kind == .transfer ? nil : category
        t.tags = tags; t.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if tx == nil { context.insert(t) }
        context.saveOrReport()
        return t
    }
}

struct EntryView: View {
    var editing: Transaction?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.sortOrder) private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @Query(sort: \Category.sortOrder) private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @Query(sort: \Transaction.date, order: .reverse) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @State private var vm: EntryViewModel
    @State private var showCategories = false
    @State private var confirmDelete = false
    @FocusState private var amountFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 52

    init(editing: Transaction? = nil) {
        self.editing = editing
        _vm = State(initialValue: EntryViewModel(editing: editing))
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived || $0.id == vm.account?.id } }
    private var categoryKind: CategoryKind { vm.kind == .income ? .income : .expense }

    /// Recently used categories for the current kind, falling back to the first ones.
    private var chipCategories: [Category] {
        var seen = Set<UUID>(), result: [Category] = []
        for t in transactions where t.kind == vm.kind {
            if let c = t.category, !c.isArchived, seen.insert(c.id).inserted { result.append(c) }
            if result.count == 7 { break }
        }
        if result.count < 4 {
            for c in categories where c.kind == categoryKind && c.parent == nil && !c.isArchived && seen.insert(c.id).inserted {
                result.append(c)
                if result.count == 7 { break }
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Picker("Тип", selection: $vm.kind) {
                        ForEach(TxKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                        TextField("0", text: $vm.amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .font(.system(size: amountSize, weight: .semibold, design: .serif))
                            .minimumScaleFactor(0.5)
                            .accessibilityLabel(Text("Сумма"))
                        Text(settings.currency.symbol).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.vertical, Theme.Spacing.s)

                    if vm.kind != .transfer { categorySection }

                    VStack(spacing: 0) {
                        accountRow(title: vm.kind == .transfer ? L("Со счёта") : L("Счёт"), selection: $vm.account)
                        Divider().overlay(Theme.Colors.border)
                        if vm.kind == .transfer {
                            accountRow(title: L("На счёт"), selection: $vm.toAccount)
                            Divider().overlay(Theme.Colors.border)
                        }
                        DatePicker("Дата", selection: $vm.date, displayedComponents: .date).padding(Theme.Spacing.m)
                        Divider().overlay(Theme.Colors.border)
                        TextField("Теги через пробел", text: $vm.tagsText).textInputAutocapitalization(.never).padding(Theme.Spacing.m)
                        Divider().overlay(Theme.Colors.border)
                        TextField("Заметка", text: $vm.note, axis: .vertical).padding(Theme.Spacing.m)
                    }
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.Colors.border))

                    if editing != nil {
                        Button("Удалить операцию", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(editing == nil ? "Новая операция" : "Операция")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button("Сохранить", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!vm.canSave)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Theme.Colors.background)
            }
            .sheet(isPresented: $showCategories) {
                CategoryPicker(kind: categoryKind, selection: $vm.category).presentationDetents([.medium, .large])
            }
            .confirmationDialog("Удалить операцию?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    if let tx = editing {
                        dismiss()
                        // Delete once the sheet is off screen, so nothing re-renders from the object while it goes away.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(tx); context.saveOrReport() }
                    } else { dismiss() }
                }
            }
        }
        .onAppear {
            if vm.account == nil { vm.account = activeAccounts.first }
            if editing == nil { amountFocused = true }
        }
        .onChange(of: vm.amountText) { _, new in
            let clean = MoneyParser.sanitize(new)
            if clean != new { vm.amountText = clean }
        }
        .onChange(of: vm.kind) { _, new in
            if new != .transfer, let c = vm.category, c.kind != categoryKind { vm.category = nil }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Категория").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(chipCategories) { c in
                        Button { vm.category = c } label: {
                            Label(c.name, systemImage: c.icon).chip(selected: vm.category?.id == c.id)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { showCategories = true } label: {
                        Label(vm.category.flatMap { c in chipCategories.contains { $0.id == c.id } ? nil : c.fullName } ?? L("Все"), systemImage: "ellipsis")
                            .chip(selected: vm.category.map { c in !chipCategories.contains { $0.id == c.id } } ?? false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accountRow(title: String, selection: Binding<Account?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                ForEach(activeAccounts) { a in Button(a.name) { selection.wrappedValue = a } }
            } label: {
                Text(selection.wrappedValue?.name ?? L("Выбрать")).foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.m)
    }

    private func save() {
        guard let t = vm.commit(into: editing, context: context) else { return }
        if editing == nil { BudgetNotifier.checkExceeded(after: t, in: context, settings: settings) }
        dismiss()
    }
}
