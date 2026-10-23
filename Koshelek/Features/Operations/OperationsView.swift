import SwiftUI
import SwiftData

struct OperationsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @Query private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @Query private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @State private var filter = TransactionFilter()
    @State private var showFilter = false

    private var index: CategoryIndex { CategoryIndex(categories.map(\.info)) }

    /// The filter without references to categories or accounts that no longer exist (they would silently match nothing).
    private var effectiveFilter: TransactionFilter {
        var f = filter
        f.categoryIDs.formIntersection(categories.map(\.id))
        f.accountIDs.formIntersection(accounts.map(\.id))
        return f
    }

    private var filtered: [Transaction] {
        let filter = effectiveFilter
        guard filter.isActive else { return transactions }
        let ids = Set(filter.apply(transactions.records, index: index).map(\.id))
        return transactions.filter { ids.contains($0.id) }
    }

    private struct DayGroup: Identifiable {
        var day: Date
        var rows: [TxRowData]
        /// Net effect of the day on overall money; transfers are excluded.
        var total: Decimal
        var id: Date { day }
    }

    private var groups: [DayGroup] {
        let money = settings.money
        return Dictionary(grouping: filtered) { Calendar.app.startOfDay(for: $0.date) }.map { day, items in
            let total: Decimal = items.reduce(0) { sum, t in
                switch t.kind {
                case .income: sum + t.amount
                case .expense: sum - t.amount
                case .transfer: sum
                }
            }
            return DayGroup(day: day, rows: items.map { $0.rowData(money) }, total: total)
        }
        .sorted { $0.day > $1.day }
    }

    private func transaction(_ id: UUID) -> Transaction? { transactions.first { $0.id == id } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            ScreenHeader(title: L("Операции")) {
                HeaderButton(systemImage: filter.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                             label: L("Фильтры")) { showFilter = true }
            }
            .padding(.horizontal, Theme.Spacing.l)
            searchField
            List {
                if transactions.isEmpty {
                    EmptyStateView(icon: "tray", title: L("Операций пока нет"), hint: L("Добавьте первую операцию кнопкой «+»."))
                        .listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: L("Ничего не найдено"), hint: L("Попробуйте изменить поисковый запрос или фильтры."))
                        .listRowBackground(Color.clear)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.rows) { row in
                            Button { if let t = transaction(row.id) { router.entryRequest = EntryRequest(transactionID: t.id) } } label: { TransactionRow(row: row) }
                                .buttonStyle(.plain)
                                .listRowBackground(Theme.Colors.card)
                                .swipeActions {
                                    Button("Удалить", role: .destructive) {
                                        if let t = transaction(row.id) { context.delete(t); context.saveOrReport() }
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(DateText.day(group.day))
                            Spacer()
                            Text(settings.money.string(group.total, signed: true))
                        }
                        .font(Theme.Fonts.caption)
                    }.listRowBackground(Theme.Colors.card)
                }
                Color.clear.frame(height: 70).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyleWarm()
            }
            .screenBackground()
            .navigationTitle("Операции")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFilter) { FilterSheet(filter: $filter) }
            .withFAB()
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textSecondary)
            TextField("Поиск по заметке, тегу, категории", text: $filter.text)
                .submitLabel(.search)
            if !filter.text.isEmpty {
                Button { filter.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.textSecondary) }
                    .accessibilityLabel(Text("Очистить поиск"))
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.Colors.border, lineWidth: 1))
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
    }
}

struct FilterSheet: View {
    @Binding var filter: TransactionFilter
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @Query(sort: \Category.sortOrder) private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @Query private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @State private var useFrom = false
    @State private var useTo = false
    @State private var from = Date()
    @State private var to = Date()
    @State private var minText = ""
    @State private var maxText = ""

    private func roots(_ kind: CategoryKind) -> [Category] {
        categories.filter { $0.kind == kind && $0.parent == nil && !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var allTags: [String] { Array(Set(transactions.flatMap(\.tags))).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section("Дата") {
                    Toggle("С даты", isOn: $useFrom)
                    if useFrom { DatePicker("С", selection: $from, displayedComponents: .date) }
                    Toggle("По дату", isOn: $useTo)
                    if useTo { DatePicker("По", selection: $to, displayedComponents: .date) }
                }.listRowBackground(Theme.Colors.card)
                Section("Сумма") {
                    TextField("От", text: $minText).keyboardType(.decimalPad)
                    TextField("До", text: $maxText).keyboardType(.decimalPad)
                }.listRowBackground(Theme.Colors.card)
                ForEach(CategoryKind.allCases) { kind in
                    Section(kind.title) {
                        ForEach(roots(kind)) { c in
                            toggleRow(c.name, icon: c.icon, color: c.colorKey, isOn: filter.categoryIDs.contains(c.id)) { toggle(&filter.categoryIDs, c.id) }
                            ForEach(c.children.live.sorted { $0.sortOrder < $1.sortOrder }) { s in
                                toggleRow(s.name, icon: s.icon, color: s.colorKey, isOn: filter.categoryIDs.contains(s.id)) { toggle(&filter.categoryIDs, s.id) }
                                    .padding(.leading, Theme.Spacing.xl)
                            }
                        }
                    }
                    .listRowBackground(Theme.Colors.card)
                }
                Section("Счета") {
                    ForEach(accounts) { a in
                        toggleRow(a.name, icon: a.icon, color: a.colorKey, isOn: filter.accountIDs.contains(a.id)) { toggle(&filter.accountIDs, a.id) }
                    }
                }.listRowBackground(Theme.Colors.card)
                if !allTags.isEmpty {
                    Section("Теги") {
                        FlowLayout(spacing: Theme.Spacing.s) {
                            ForEach(allTags, id: \.self) { tag in
                                Button { toggle(&filter.tags, tag) } label: { Text("#" + tag).chip(selected: filter.tags.contains(tag)) }.buttonStyle(.plain)
                            }
                        }
                    }.listRowBackground(Theme.Colors.card)
                }
                Section {
                    Button("Сбросить фильтры", role: .destructive) {
                        let text = filter.text
                        filter = TransactionFilter(); filter.text = text
                        useFrom = false; useTo = false; minText = ""; maxText = ""
                    }
                }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { apply(); dismiss() } } }
        }
        .onAppear {
            useFrom = filter.from != nil; useTo = filter.to != nil
            from = filter.from ?? Date(); to = filter.to ?? Date()
            minText = filter.minAmount.map { "\($0)" } ?? ""; maxText = filter.maxAmount.map { "\($0)" } ?? ""
        }
        // Category, account and tag toggles apply immediately, so dates and amounts must not be lost on a swipe-down either.
        .onDisappear { apply() }
        .presentationDetents([.large])
    }

    private func apply() {
        filter.from = useFrom ? from : nil
        filter.to = useTo ? to : nil
        filter.minAmount = MoneyParser.parse(minText)
        filter.maxAmount = MoneyParser.parse(maxText)
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func toggleRow(_ title: String, icon: String, color: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                IconBadge(icon: icon, colorKey: color, size: 28)
                Text(title).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
