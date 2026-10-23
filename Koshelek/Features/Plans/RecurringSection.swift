import SwiftUI
import SwiftData

struct RecurringSection: View {
    @Binding var showAdd: Bool
    @Environment(AppSettings.self) private var settings
    @Query(sort: \RecurringRule.startDate) private var rulesQuery: [RecurringRule]
    private var rules: [RecurringRule] { rulesQuery.live }
    @State private var editing: ItemID?

    private struct UpcomingRow: Identifiable { var id: String; var title: String; var dateText: String; var amountText: String; var icon: String; var colorKey: String; var date: Date }
    private struct RuleRow: Identifiable { var id: UUID; var title: String; var frequency: String; var amountText: String; var icon: String; var colorKey: String; var isActive: Bool }

    private func title(_ r: RecurringRule) -> String { r.note.isEmpty ? (r.category?.name ?? L("Платёж")) : r.note }

    private var upcoming: [UpcomingRow] {
        let now = Date()
        let until = Calendar.app.date(byAdding: .day, value: 30, to: now)!
        return rules.filter(\.isActive).flatMap { r in
            RecurrenceGenerator.upcoming(r.schedule, after: now, until: until).map { d in
                UpcomingRow(id: "\(r.id)-\(d.timeIntervalSince1970)", title: title(r), dateText: DateText.short(d),
                            amountText: settings.money.string(r.kind == .income ? r.amount : -r.amount, signed: r.kind == .income),
                            icon: r.category?.icon ?? "arrow.triangle.2.circlepath", colorKey: r.category?.colorKey ?? "stone", date: d)
            }
        }
        .sorted { $0.date < $1.date }
    }

    private var ruleRows: [RuleRow] {
        rules.map { r in
            RuleRow(id: r.id, title: title(r), frequency: r.isActive ? r.frequency.title : L("Приостановлено"),
                    amountText: settings.money.string(r.amount), icon: r.category?.icon ?? "arrow.triangle.2.circlepath",
                    colorKey: r.category?.colorKey ?? "stone", isActive: r.isActive)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if rules.isEmpty {
                    EmptyStateView(icon: "arrow.triangle.2.circlepath", title: L("Регулярных платежей нет"),
                                   hint: L("Добавьте аренду или подписки, и операции будут создаваться сами."))
                        .card()
                    Button("Добавить платёж") { showAdd = true }.buttonStyle(PrimaryButtonStyle())
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: L("Ближайшие 30 дней"))
                        if upcoming.isEmpty { Text("Ближайших платежей нет.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                        ForEach(upcoming.prefix(15)) { u in
                            AdaptiveRow {
                                HStack(spacing: Theme.Spacing.m) {
                                    IconBadge(icon: u.icon, colorKey: u.colorKey, size: 32)
                                    VStack(alignment: .leading) {
                                        Text(u.title)
                                        Text(u.dateText).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                }
                            } trailing: {
                                Text(u.amountText).font(Theme.Fonts.amount)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: L("Правила"))
                        ForEach(ruleRows) { r in
                            Button { editing = ItemID(id: r.id) } label: {
                                AdaptiveRow {
                                    HStack(spacing: Theme.Spacing.m) {
                                        IconBadge(icon: r.icon, colorKey: r.colorKey, size: 32)
                                        VStack(alignment: .leading) {
                                            Text(r.title).foregroundStyle(Theme.Colors.textPrimary)
                                            Text(r.frequency).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                        }
                                    }
                                } trailing: {
                                    Text(r.amountText).font(Theme.Fonts.amount).foregroundStyle(Theme.Colors.textPrimary)
                                }
                                .opacity(r.isActive ? 1 : 0.55)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showAdd) { RecurringEditView(rule: nil) }
        .sheet(item: $editing) { item in
            if let rule = rules.first(where: { $0.id == item.id }) { RecurringEditView(rule: rule) }
        }
    }
}

struct RecurringEditView: View {
    let rule: RecurringRule?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Account.sortOrder) private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @State private var kind = TxKind.expense
    @State private var amountText = ""
    @State private var note = ""
    @State private var category: Category?
    @State private var account: Account?
    @State private var frequency = Frequency.monthly
    @State private var start = Date()
    @State private var hasEnd = false
    @State private var end = Calendar.app.date(byAdding: .year, value: 1, to: Date())!
    @State private var isActive = true
    @State private var pick = false

    private var amount: Decimal? { MoneyParser.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $kind) { Text("Расход").tag(TxKind.expense); Text("Доход").tag(TxKind.income) }.pickerStyle(.segmented)
                    HStack {
                        TextField("Сумма", text: $amountText).keyboardType(.decimalPad)
                        Text(settings.currency.symbol).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    TextField("Название, например «Аренда»", text: $note)
                    Button { pick = true } label: {
                        HStack { Text("Категория").foregroundStyle(Theme.Colors.textPrimary); Spacer(); Text(category?.fullName ?? L("Выбрать")).foregroundStyle(Theme.Colors.accent) }
                    }
                    Picker("Счёт", selection: $account) {
                        ForEach(accounts.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0)) }
                    }
                }.listRowBackground(Theme.Colors.card)
                Section("Расписание") {
                    Picker("Повтор", selection: $frequency) { ForEach(Frequency.allCases) { Text($0.title).tag($0) } }
                    DatePicker("Начало", selection: $start, displayedComponents: .date)
                    Toggle("Дата окончания", isOn: $hasEnd)
                    if hasEnd { DatePicker("Окончание", selection: $end, in: start..., displayedComponents: .date) }
                    Toggle("Активно", isOn: $isActive)
                }.listRowBackground(Theme.Colors.card)
                if let rule {
                    Section { Button("Удалить правило", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(rule); context.saveOrReport() }
                    } }.listRowBackground(Theme.Colors.card)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(rule == nil ? "Новый платёж" : "Платёж")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(amount == nil || account == nil) }
            }
            .sheet(isPresented: $pick) { CategoryPicker(kind: kind == .income ? .income : .expense, selection: $category).presentationDetents([.medium, .large]) }
            // onAppear sets `kind` for an existing rule too, so only drop a category that no longer fits.
            .onChange(of: kind) { _, new in if let c = category, c.kind.txKind != new { category = nil } }
            .onAppear {
                if let r = rule {
                    kind = r.kind; amountText = NSDecimalNumber(decimal: r.amount).stringValue.replacingOccurrences(of: ".", with: ","); note = r.note
                    category = r.category; account = r.account; frequency = r.frequency; start = r.startDate
                    if let e = r.endDate { hasEnd = true; end = e }
                    isActive = r.isActive
                } else { account = accounts.first { !$0.isArchived } }
            }
        }
    }

    private func save() {
        guard let amount, let account else { return }
        let s = Calendar.app.startOfDay(for: start)
        let e = hasEnd ? max(Calendar.app.startOfDay(for: end), s) : nil
        if let r = rule {
            if r.startDate != s || r.frequency != frequency { r.lastGeneratedDate = nil }
            r.kind = kind; r.amount = amount; r.note = note; r.category = category; r.account = account
            r.frequency = frequency; r.startDate = s; r.endDate = e; r.isActive = isActive
        } else {
            let r = RecurringRule(kind: kind, amount: amount, note: note, frequency: frequency, startDate: s, endDate: e, account: account, category: category)
            r.isActive = isActive
            context.insert(r)
        }
        context.saveOrReport()
        RecurringService.generateDue(in: context)
        dismiss()
    }
}
