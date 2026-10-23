import SwiftUI
import SwiftData

struct OverviewView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Account.sortOrder) private var accountsQuery: [Account]
    private var accounts: [Account] { accountsQuery.live }
    @Query(sort: \Transaction.date, order: .reverse) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @Query private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @Query private var budgetsQuery: [Budget]
    private var budgets: [Budget] { budgetsQuery.live }
    @Query private var rulesQuery: [RecurringRule]
    private var rules: [RecurringRule] { rulesQuery.live }
    private var active: [Account] { accounts.filter { !$0.isArchived } }
    private var records: [TxRecord] { transactions.records }
    private var balances: [UUID: Decimal] {
        BalanceCalculator.balances(initial: Dictionary(active.map { ($0.id, $0.initialBalance) }, uniquingKeysWith: { a, _ in a }), transactions: records)
    }
    private var month: Period { .containing(Date(), kind: .month) }
    private var index: CategoryIndex { CategoryIndex(categories.map(\.info)) }

    private var forecast: Forecast {
        OverviewMetrics.forecast(balance: BalanceCalculator.total(balances), records: records, rules: rules)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    ScreenHeader(title: L("Обзор"))
                    balanceCard
                    if transactions.isEmpty {
                        EmptyStateView(icon: "tray", title: L("Пока нет операций"), hint: L("Нажмите «+», чтобы добавить первый расход или доход."))
                            .card()
                    } else {
                        forecastCard
                    }
                    accountsCard
                    if !budgets.isEmpty { budgetsCard }
                    if !transactions.isEmpty { recentCard }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, 96)
            }
            .screenBackground()
            .navigationTitle("Обзор")
            .toolbar(.hidden, for: .navigationBar)
            .withFAB()
        }
    }

    private var balanceCard: some View {
        let income = AnalyticsEngine.total(records, kind: .income, in: month)
        let expense = AnalyticsEngine.total(records, kind: .expense, in: month)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Общий баланс").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            Text(settings.money.string(BalanceCalculator.total(balances))).font(Theme.Fonts.bigNumber)
                .minimumScaleFactor(0.5).lineLimit(1)
            AdaptiveStack(spacing: Theme.Spacing.xl) {
                stat(title: L("Доходы за месяц"), value: settings.money.string(income), color: Theme.Colors.income)
                stat(title: L("Расходы за месяц"), value: settings.money.string(expense), color: Theme.Colors.expense)
            }
            .padding(.top, Theme.Spacing.s)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func stat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            Text(value).font(Theme.Fonts.amount).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var forecastCard: some View {
        let f = forecast
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Прогноз на конец месяца").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            Text(settings.money.string(f.projectedBalance)).font(Theme.Fonts.title)
                .foregroundStyle(f.projectedBalance < 0 ? Theme.Colors.expense : Theme.Colors.textPrimary)
            Text(LF("Тратите в среднем %@ в день, осталось дней: %d, плановые платежи: %@.",
                    settings.money.string(f.averageDailySpending), f.remainingDays, settings.money.string(f.scheduledNet, signed: true)))
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private struct AccountRow: Identifiable { var id: UUID; var name: String; var icon: String; var colorKey: String; var balance: String }

    private var accountRows: [AccountRow] {
        active.map { AccountRow(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey, balance: settings.money.string(balances[$0.id] ?? 0)) }
    }

    private func open(_ id: UUID) {
        if let t = transactions.first(where: { $0.id == id }) { router.entryRequest = EntryRequest(transactionID: t.id) }
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Счета"))
            ForEach(accountRows) { a in
                AdaptiveRow {
                    HStack(spacing: Theme.Spacing.m) { IconBadge(icon: a.icon, colorKey: a.colorKey); Text(a.name) }
                } trailing: {
                    Text(a.balance).font(Theme.Fonts.amount)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var budgetsCard: some View {
        let rows = BudgetRows.make(budgets, records: records, month: month, index: index)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Бюджеты месяца"))
            ForEach(rows.prefix(3)) { row in BudgetRow(row: row) }
        }
        .card()
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Последние операции"))
            ForEach(transactions.prefix(5).map { $0.rowData(settings.money) }) { row in
                Button { open(row.id) } label: { TransactionRow(row: row) }.buttonStyle(.plain)
            }
        }
        .card()
    }
}

struct BudgetRow: View {
    @Environment(AppSettings.self) private var settings
    let row: BudgetRowData
    private var progress: BudgetProgress { row.progress }

    static func color(for state: BudgetState) -> Color {
        switch state {
        case .normal: Theme.Colors.income
        case .warning: Theme.Colors.warning
        case .exceeded: Theme.Colors.expense
        }
    }

    private var stateText: String {
        switch progress.state {
        case .normal: LF("Осталось %@", settings.money.string(progress.remaining))
        case .warning: LF("Почти исчерпан: осталось %@", settings.money.string(progress.remaining))
        case .exceeded: LF("Превышен на %@", settings.money.string(-progress.remaining))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            AdaptiveRow {
                HStack(spacing: Theme.Spacing.m) {
                    IconBadge(icon: row.icon, colorKey: row.colorKey, size: 28)
                    Text(row.name)
                }
            } trailing: {
                Text("\(settings.money.number(progress.spent)) / \(settings.money.string(progress.limit))")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            ProgressBar(value: progress.ratio, color: Self.color(for: progress.state))
            Text(stateText).font(Theme.Fonts.caption)
                .foregroundStyle(progress.state == .normal ? Theme.Colors.textSecondary : Self.color(for: progress.state))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(PercentFormatter.string(progress.ratio)))
    }
}
