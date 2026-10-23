import SwiftUI
import SwiftData

enum PlanSection: String, CaseIterable, Identifiable {
    case budgets, goals, recurring
    var id: String { rawValue }
    var title: String {
        switch self {
        case .budgets: L("Бюджеты")
        case .goals: L("Цели")
        case .recurring: L("Регулярные")
        }
    }
}

struct PlansView: View {
    @State private var section = PlanSection.budgets
    @State private var addBudget = false
    @State private var addGoal = false
    @State private var addRule = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: L("Планы")) {
                    HeaderButton(systemImage: "plus", label: L("Добавить")) {
                        switch section {
                        case .budgets: addBudget = true
                        case .goals: addGoal = true
                        case .recurring: addRule = true
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                Picker("Раздел", selection: $section) {
                    ForEach(PlanSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)

                switch section {
                case .budgets: BudgetsSection(showAdd: $addBudget)
                case .goals: GoalsSection(showAdd: $addGoal)
                case .recurring: RecurringSection(showAdd: $addRule)
                }
            }
            .screenBackground()
            .navigationTitle("Планы")
            .toolbar(.hidden, for: .navigationBar)
            .withFAB()
        }
    }
}

// MARK: Budgets

struct BudgetsSection: View {
    @Binding var showAdd: Bool
    @Environment(AppSettings.self) private var settings
    @Query private var budgetsQuery: [Budget]
    private var budgets: [Budget] { budgetsQuery.live }
    @Query private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @Query private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @State private var editing: ItemID?

    private var month: Period { .containing(Date(), kind: .month) }
    private var index: CategoryIndex { CategoryIndex(categories.map(\.info)) }

    var body: some View {
        let items = BudgetRows.make(budgets, records: transactions.records, month: month, index: index)

        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if items.isEmpty {
                    EmptyStateView(icon: "chart.bar.doc.horizontal", title: L("Бюджетов пока нет"),
                                   hint: L("Задайте месячный лимит на категорию, например на «Еду», и следите за прогрессом."))
                        .card()
                    Button("Создать бюджет") { showAdd = true }.buttonStyle(PrimaryButtonStyle())
                } else {
                    let limit = items.reduce(Decimal(0)) { $0 + $1.progress.limit }
                    let spent = items.reduce(Decimal(0)) { $0 + $1.progress.spent }
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(month.title()).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                        Text(LF("%@ из %@", settings.money.number(spent), settings.money.string(limit))).font(Theme.Fonts.title)
                        ProgressBar(value: limit == 0 ? 0 : (spent / limit).doubleValue, color: Theme.Colors.accent)
                    }
                    .card()
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        ForEach(items) { row in
                            Button { editing = ItemID(id: row.id) } label: { BudgetRow(row: row) }.buttonStyle(.plain)
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showAdd) { BudgetEditView(budget: nil) }
        .sheet(item: $editing) { item in
            if let budget = budgets.first(where: { $0.id == item.id }) { BudgetEditView(budget: budget) }
        }
    }
}

struct BudgetEditView: View {
    let budget: Budget?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query private var budgetsQuery: [Budget]
    private var budgets: [Budget] { budgetsQuery.live }
    @State private var category: Category?
    @State private var limitText = ""
    @State private var pick = false

    private var limit: Decimal? { MoneyParser.parse(limitText).flatMap { $0 > 0 ? $0 : nil } }
    private var duplicate: Bool { category.map { c in budgets.contains { $0.category?.id == c.id && $0.id != budget?.id } } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { pick = true } label: {
                        HStack {
                            Text("Категория").foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Text(category?.fullName ?? L("Выбрать")).foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    HStack {
                        TextField("Лимит на месяц", text: $limitText).keyboardType(.decimalPad)
                        Text(settings.currency.symbol).foregroundStyle(Theme.Colors.textSecondary)
                    }
                } footer: {
                    if duplicate { Text("Для этой категории бюджет уже есть.").foregroundStyle(Theme.Colors.expense) }
                    else { Text("Предупреждение появляется при 80% лимита, а при превышении 100% бюджет подсвечивается.") }
                }.listRowBackground(Theme.Colors.card)
                if let budget {
                    Section { Button("Удалить бюджет", role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(budget); context.saveOrReport() }
                    } }.listRowBackground(Theme.Colors.card)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle("Бюджет")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(limit == nil || category == nil || duplicate) }
            }
            .sheet(isPresented: $pick) { CategoryPicker(kind: .expense, selection: $category).presentationDetents([.medium, .large]) }
            .onAppear {
                if let b = budget { category = b.category; limitText = NSDecimalNumber(decimal: b.monthlyLimit).stringValue.replacingOccurrences(of: ".", with: ",") }
            }
        }
    }

    private func save() {
        guard let limit, let category else { return }
        if let b = budget { b.monthlyLimit = limit; b.category = category } else { context.insert(Budget(monthlyLimit: limit, category: category)) }
        context.saveOrReport()
        dismiss()
    }
}

// MARK: Goals

struct GoalsSection: View {
    @Binding var showAdd: Bool
    @Environment(AppSettings.self) private var settings
    @Query(sort: \SavingsGoal.createdAt) private var goalsQuery: [SavingsGoal]
    private var goals: [SavingsGoal] { goalsQuery.live }

    private struct GoalCard: Identifiable {
        var id: UUID
        var name: String, icon: String, colorKey: String
        var deadline: String?
        var progress: Double
        var amounts: String
    }

    private var cards: [GoalCard] {
        goals.map { g in
            GoalCard(id: g.id, name: g.name, icon: g.icon, colorKey: g.colorKey,
                     deadline: g.deadline.map { LF("до %@", DateText.short($0)) }, progress: g.progress,
                     amounts: LF("%@ из %@", settings.money.number(g.saved), settings.money.string(g.targetAmount)))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                if goals.isEmpty {
                    EmptyStateView(icon: "star", title: L("Целей пока нет"), hint: L("Поставьте цель, например «Отпуск», и откладывайте на неё понемногу."))
                        .card()
                    Button("Создать цель") { showAdd = true }.buttonStyle(PrimaryButtonStyle())
                }
                ForEach(cards) { c in
                    NavigationLink { GoalDetailView(goalID: c.id) } label: {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            AdaptiveRow {
                                HStack(spacing: Theme.Spacing.m) {
                                    IconBadge(icon: c.icon, colorKey: c.colorKey)
                                    VStack(alignment: .leading) {
                                        Text(c.name).foregroundStyle(Theme.Colors.textPrimary)
                                        if let d = c.deadline { Text(d).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                                    }
                                }
                            } trailing: {
                                Text(PercentFormatter.string(c.progress)).font(Theme.Fonts.amount).foregroundStyle(Theme.Colors.textPrimary)
                            }
                            ProgressBar(value: c.progress, color: Theme.Palette.color(c.colorKey))
                            Text(c.amounts).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .card()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, 96)
        }
        .sheet(isPresented: $showAdd) { GoalEditView(goal: nil) }
    }
}

struct GoalEditView: View {
    let goal: SavingsGoal?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var name = ""
    @State private var targetText = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.app.date(byAdding: .month, value: 6, to: Date())!
    @State private var icon = "star"
    @State private var colorKey = "olive"

    private var target: Decimal? { MoneyParser.parse(targetText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    HStack {
                        TextField("Сумма цели", text: $targetText).keyboardType(.decimalPad)
                        Text(settings.currency.symbol).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Toggle("Срок", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Дата", selection: $deadline, in: Date()..., displayedComponents: .date) }
                }.listRowBackground(Theme.Colors.card)
                Section("Значок и цвет") { IconColorPicker(icon: $icon, colorKey: $colorKey) }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(goal == nil ? "Новая цель" : "Цель")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(target == nil || name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard let g = goal else { return }
                name = g.name; icon = g.icon; colorKey = g.colorKey
                targetText = NSDecimalNumber(decimal: g.targetAmount).stringValue.replacingOccurrences(of: ".", with: ",")
                if let d = g.deadline { hasDeadline = true; deadline = d }
            }
        }
    }

    private func save() {
        guard let target else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        if let g = goal {
            g.name = n; g.icon = icon; g.colorKey = colorKey; g.targetAmount = target; g.deadline = hasDeadline ? deadline : nil
        } else {
            context.insert(SavingsGoal(name: n, icon: icon, colorKey: colorKey, targetAmount: target, deadline: hasDeadline ? deadline : nil))
        }
        context.saveOrReport()
        dismiss()
    }
}

struct GoalDetailView: View {
    let goalID: UUID
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var goalsQuery: [SavingsGoal]
    @State private var editing = false
    @State private var adding = false
    @State private var confirmDelete = false

    /// Looked up on every render, so nothing here holds a goal that has been deleted.
    private var goal: SavingsGoal? { goalsQuery.live.first { $0.id == goalID } }

    private struct ContributionRow: Identifiable { var id: UUID; var dateText: String; var note: String; var amountText: String }

    private func hint(for goal: SavingsGoal) -> String? {
        let remaining = goal.targetAmount - goal.saved
        guard remaining > 0 else { return L("Цель достигнута!") }
        guard let d = goal.deadline, d > Date() else { return nil }
        let months = max(Calendar.app.dateComponents([.month], from: Date(), to: d).month ?? 1, 1)
        return LF("Чтобы успеть к сроку, откладывайте около %@ в месяц.", settings.money.string((remaining / Decimal(months)).rounded(0, .up)))
    }

    var body: some View {
        if let goal { content(goal) } else { Color.clear.screenBackground() }
    }

    private func deleteContribution(_ id: UUID) {
        guard let c = goal?.contributions.live.first(where: { $0.id == id }) else { return }
        context.delete(c)
        context.saveOrReport()
    }

    private func content(_ goal: SavingsGoal) -> some View {
        let live = goal.contributions.live
        let rows = live.sorted { $0.date > $1.date }.map {
            ContributionRow(id: $0.id, dateText: DateText.short($0.date), note: $0.note, amountText: settings.money.string($0.amount, signed: $0.amount > 0))
        }
        var sum = 0.0
        let cumulative: [(Date, Double)] = live.sorted { $0.date < $1.date }.map { c in sum += c.amount.doubleValue; return (c.date, sum) }
        let progress = goal.progress, colorKey = goal.colorKey
        let amounts = LF("%@ из %@", settings.money.number(goal.saved), settings.money.string(goal.targetAmount))
        let hintText = hint(for: goal)
        return ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                VStack(spacing: Theme.Spacing.m) {
                    ZStack {
                        Circle().stroke(Theme.Colors.cardRaised, lineWidth: 14)
                        Circle().trim(from: 0, to: progress)
                            .stroke(Theme.Palette.color(colorKey), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.3), value: progress)
                        VStack(spacing: 2) {
                            Text(PercentFormatter.string(progress)).font(Theme.Fonts.bigNumber)
                            Text(amounts).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .frame(width: 200, height: 200)
                    .padding(Theme.Spacing.m)
                    .accessibilityElement(children: .combine)
                    if let hintText { Text(hintText).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center) }
                    Button("Пополнить") { adding = true }.buttonStyle(PrimaryButtonStyle())
                }
                .card()

                if cumulative.count > 1 {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: L("Накопления со временем"))
                        GoalChart(points: cumulative, color: Theme.Palette.color(colorKey))
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: L("Взносы"))
                    if rows.isEmpty { Text("Взносов пока нет.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                    ForEach(rows) { c in
                        AdaptiveRow {
                            VStack(alignment: .leading) {
                                Text(c.dateText)
                                if !c.note.isEmpty { Text(c.note).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                            }
                        } trailing: {
                            HStack {
                                Text(c.amountText).font(Theme.Fonts.amount)
                                Button { deleteContribution(c.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).foregroundStyle(Theme.Colors.textSecondary).accessibilityLabel(Text("Удалить взнос"))
                            }
                        }
                    }
                }
                .card()
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Изменить") { editing = true }
                    Button("Удалить цель", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle").accessibilityLabel(Text("Действия с целью")) }
            }
        }
        .sheet(isPresented: $editing) { GoalEditView(goal: goal) }
        .sheet(isPresented: $adding) { ContributionView(goal: goal) }
        .confirmationDialog("Удалить цель и все взносы?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(goal); context.saveOrReport() }
            }
        }
    }
}

import Charts
struct GoalChart: View {
    let points: [(Date, Double)]
    let color: Color
    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(x: .value("Дата", p.0), y: .value("Накоплено", p.1)).foregroundStyle(color.opacity(0.18))
                LineMark(x: .value("Дата", p.0), y: .value("Накоплено", p.1)).foregroundStyle(color).interpolationMethod(.monotone)
                PointMark(x: .value("Дата", p.0), y: .value("Накоплено", p.1)).foregroundStyle(color)
            }
        }
        .frame(height: 140)
        .accessibilityLabel(Text("График накоплений"))
    }
}

struct ContributionView: View {
    let goal: SavingsGoal
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var withdraw = false
    @FocusState private var focused: Bool

    private var amount: Decimal? { MoneyParser.parse(amountText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Тип", selection: $withdraw) { Text("Взнос").tag(false); Text("Снятие").tag(true) }.pickerStyle(.segmented)
                    HStack {
                        TextField("Сумма", text: $amountText).keyboardType(.decimalPad).focused($focused)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                        Text(settings.currency.symbol).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    DatePicker("Дата", selection: $date, displayedComponents: .date)
                    TextField("Заметка", text: $note)
                }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(goal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        guard let amount else { return }
                        context.insert(GoalContribution(amount: withdraw ? -amount : amount, date: date, note: note, goal: goal))
                        context.saveOrReport()
                        dismiss()
                    }
                    .disabled(amount == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
