import SwiftUI
import SwiftData
import Charts

@Observable final class AnalyticsViewModel {
    var period = Period.containing(Date(), kind: .month)
    var customFrom = Calendar.app.dateInterval(of: .month, for: Date())!.start
    var customTo = Date()

    var kind: PeriodKind {
        get { period.kind }
        set {
            period = newValue == .custom ? .custom(from: customFrom, to: customTo) : .containing(Date(), kind: newValue)
        }
    }

    var canShiftForward: Bool { period.kind != .custom && period.end <= Date() }

    func shift(_ n: Int) { period = period.shifted(by: n) }
    func applyCustom() { period = .custom(from: customFrom, to: customTo) }

    /// Monthly bars: 12 months of a selected year, otherwise the 6 months ending with the period.
    func monthRange(calendar: Calendar = .app) -> (first: Date, count: Int) {
        if period.kind == .year { return (period.start, 12) }
        let last = calendar.dateInterval(of: .month, for: period.lastDay)!.start
        return (calendar.date(byAdding: .month, value: -5, to: last)!, 6)
    }

    /// Finds the slice under a cumulative chart angle value.
    func slice(at angle: Double, in slices: [CategorySlice]) -> CategorySlice? {
        var acc = 0.0
        for s in slices {
            acc += s.amount.doubleValue
            if angle <= acc { return s }
        }
        return nil
    }
}

struct CategoryRoute: Hashable { var id: UUID? }

struct AnalyticsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Transaction.date, order: .reverse) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @Query private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    @State private var vm = AnalyticsViewModel()
    @State private var path: [CategoryRoute] = []
    @State private var selectedAngle: Double?

    private var records: [TxRecord] { transactions.records }
    private var index: CategoryIndex { CategoryIndex(categories.map(\.info)) }
    private var slices: [CategorySlice] { AnalyticsEngine.breakdown(records, in: vm.period, index: index) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    ScreenHeader(title: L("Аналитика"))
                    PeriodSwitcher(vm: vm)
                    summaryCard
                    donutCard
                    if !slices.isEmpty { comparisonCard }
                    monthlyCard
                    if !slices.isEmpty { topCard }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, 96)
            }
            .screenBackground()
            .navigationTitle("Аналитика")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CategoryRoute.self) { CategoryDetailView(route: $0, period: vm.period) }
            .withFAB()
            .onChange(of: selectedAngle) { _, angle in
                guard let angle, let s = vm.slice(at: angle, in: slices) else { return }
                path.append(CategoryRoute(id: s.id))
                selectedAngle = nil
            }
        }
    }

    private func color(_ id: UUID?) -> Color {
        guard let id, let c = categories.first(where: { $0.id == id }) else { return Theme.Palette.color("stone") }
        return Theme.Palette.color(c.colorKey)
    }

    // MARK: Cards

    private var summaryCard: some View {
        let income = AnalyticsEngine.total(records, kind: .income, in: vm.period)
        let expense = AnalyticsEngine.total(records, kind: .expense, in: vm.period)
        return AdaptiveStack(spacing: Theme.Spacing.m) {
            summaryItem(L("Доходы"), income, Theme.Colors.income)
            summaryItem(L("Расходы"), expense, Theme.Colors.expense)
            summaryItem(L("Разница"), income - expense, Theme.Colors.textPrimary)
        }
        .card()
    }

    private func summaryItem(_ title: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(settings.money.string(value)).font(Theme.Fonts.amount).foregroundStyle(color).minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var donutCard: some View {
        let total = slices.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Расходы по категориям"))
            if slices.isEmpty {
                EmptyStateView(icon: "chart.pie", title: L("Нет расходов за период"), hint: L("Добавьте операции или выберите другой период."))
            } else {
                Chart(slices) { s in
                    SectorMark(angle: .value("Сумма", s.amount.doubleValue), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(color(s.id))
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(.hidden)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        if let frame = proxy.plotFrame {
                            let f = geo[frame]
                            VStack(spacing: 2) {
                                Text("Всего").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                Text(settings.money.string(total)).font(Theme.Fonts.title).minimumScaleFactor(0.5).lineLimit(1)
                            }
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .frame(width: f.width * 0.55)
                            .position(x: f.midX, y: f.midY)
                        }
                    }
                }
                .frame(height: 250)
                .accessibilityLabel(Text("Диаграмма расходов по категориям"))

                VStack(spacing: 0) {
                    ForEach(slices) { s in
                        NavigationLink(value: CategoryRoute(id: s.id)) {
                            AdaptiveRow {
                                HStack(spacing: Theme.Spacing.m) {
                                    Circle().fill(color(s.id)).frame(width: 12, height: 12)
                                    Text(index.name(of: s.id)).foregroundStyle(Theme.Colors.textPrimary)
                                }
                            } trailing: {
                                HStack(spacing: Theme.Spacing.s) {
                                    Text(settings.money.string(s.amount)).font(Theme.Fonts.amount).foregroundStyle(Theme.Colors.textPrimary)
                                    Text(PercentFormatter.string(s.share)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                        .frame(minWidth: 44, alignment: .trailing)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .card()
    }

    private var comparisonCard: some View {
        let prev = vm.period.previous()
        let label = vm.period.comparisonLabel()
        let curTotal = AnalyticsEngine.total(records, kind: .expense, in: vm.period)
        let prevTotal = AnalyticsEngine.total(records, kind: .expense, in: prev)
        let deltas = AnalyticsEngine.comparison(records, current: vm.period, previous: prev, index: index).prefix(5)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Сравнение с прошлым периодом"))
            AdaptiveRow {
                Text("Расходы")
            } trailing: {
                changeText(AnalyticsEngine.percentChange(current: curTotal, previous: prevTotal), label: label, hasCurrent: curTotal > 0)
            }
            Divider().overlay(Theme.Colors.border)
            ForEach(Array(deltas), id: \.id) { d in
                AdaptiveRow {
                    Text(index.name(of: d.id))
                } trailing: {
                    changeText(d.change, label: label, hasCurrent: d.current > 0)
                }
                .font(Theme.Fonts.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    /// Spending growth is shown in the expense tone, a decrease in the income tone.
    private func changeText(_ change: Double?, label: String, hasCurrent: Bool) -> some View {
        Group {
            if let change {
                Text("\(PercentFormatter.signed(change)) \(label)")
                    .foregroundStyle(change > 0 ? Theme.Colors.expense : (change < 0 ? Theme.Colors.income : Theme.Colors.textSecondary))
            } else {
                Text(hasCurrent ? L("новые траты") : L("без изменений")).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var monthlyCard: some View {
        let range = vm.monthRange()
        let points = AnalyticsEngine.monthly(records, from: range.first, count: range.count)
        let income = L("Доходы"), expense = L("Расходы")
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Доходы и расходы по месяцам"))
            if points.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                EmptyStateView(icon: "chart.bar", title: L("Данных пока нет"), hint: L("Здесь появится сравнение доходов и расходов по месяцам."))
            } else {
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Месяц", p.month, unit: .month), y: .value("Сумма", p.income.doubleValue))
                        .foregroundStyle(by: .value("Тип", income)).position(by: .value("Тип", income)).cornerRadius(3)
                    BarMark(x: .value("Месяц", p.month, unit: .month), y: .value("Сумма", p.expense.doubleValue))
                        .foregroundStyle(by: .value("Тип", expense)).position(by: .value("Тип", expense)).cornerRadius(3)
                }
            }
            .chartForegroundStyleScale([income: Theme.Colors.income, expense: Theme.Colors.expense])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine().foregroundStyle(Theme.Colors.border)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(compact(d)) } }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("Диаграмма доходов и расходов по месяцам"))
            }
        }
        .card()
    }

    private func compact(_ v: Double) -> String {
        v >= 1_000_000 ? LF("%@ М", String(format: "%.1f", v / 1_000_000).replacingOccurrences(of: ".", with: ","))
            : v >= 1000 ? LF("%d т", Int(v / 1000)) : String(Int(v))
    }

    private var topCard: some View {
        let top = AnalyticsEngine.topExpenses(records, in: vm.period, limit: 5)
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = top.compactMap { byID[$0.id]?.rowData(settings.money) }
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: L("Самые крупные расходы"))
            ForEach(rows) { row in
                Button { if let t = byID[row.id] { router.entryRequest = EntryRequest(transactionID: t.id) } } label: { TransactionRow(row: row) }.buttonStyle(.plain)
            }
        }
        .card()
    }
}

struct PeriodSwitcher: View {
    @Bindable var vm: AnalyticsViewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Picker("Период", selection: $vm.kind) {
                ForEach(PeriodKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if vm.kind == .custom {
                HStack {
                    DatePicker("С", selection: $vm.customFrom, displayedComponents: .date).labelsHidden()
                    Text("—").foregroundStyle(Theme.Colors.textSecondary)
                    DatePicker("По", selection: $vm.customTo, displayedComponents: .date).labelsHidden()
                }
                .onChange(of: vm.customFrom) { _, _ in vm.applyCustom() }
                .onChange(of: vm.customTo) { _, _ in vm.applyCustom() }
            } else {
                HStack {
                    Button { vm.shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(Text("Предыдущий период"))
                    Spacer()
                    Text(vm.period.title()).font(Theme.Fonts.heading)
                    Spacer()
                    Button { vm.shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(!vm.canShiftForward).accessibilityLabel(Text("Следующий период"))
                }
            }
        }
    }
}

struct CategoryDetailView: View {
    let route: CategoryRoute
    let period: Period
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Query(sort: \Transaction.date, order: .reverse) private var transactionsQuery: [Transaction]
    private var transactions: [Transaction] { transactionsQuery.live }
    @Query private var categoriesQuery: [Category]
    private var categories: [Category] { categoriesQuery.live }
    private var index: CategoryIndex { CategoryIndex(categories.map(\.info)) }
    private var category: Category? { categories.first { $0.id == route.id } }
    private var items: [Transaction] {
        transactions.filter { $0.kind == .expense && period.contains($0.date) && index.rootID(of: $0.category?.id) == route.id }
    }
    private var subs: [CategorySlice] {
        AnalyticsEngine.subBreakdown(transactions.records, in: period, rootID: route.id, index: index)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(period.title()).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    Text(settings.money.string(items.reduce(0) { $0 + $1.amount })).font(Theme.Fonts.bigNumber).minimumScaleFactor(0.5).lineLimit(1)
                }
                .card()

                if subs.count > 1 || subs.first?.id != route.id {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        SectionHeader(title: L("Подкатегории"))
                        ForEach(subs) { s in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                AdaptiveRow {
                                    Text(s.id == route.id ? L("Без подкатегории") : index.name(of: s.id))
                                } trailing: {
                                    HStack(spacing: Theme.Spacing.s) {
                                        Text(settings.money.string(s.amount)).font(Theme.Fonts.amount)
                                        Text(PercentFormatter.string(s.share)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                            .frame(minWidth: 44, alignment: .trailing)
                                    }
                                }
                                ProgressBar(value: s.share, color: Theme.Palette.color(category?.colorKey ?? "stone"))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: L("Операции"))
                    ForEach(items.map { $0.rowData(settings.money) }) { row in
                        Button { if let t = items.first(where: { $0.id == row.id }) { router.entryRequest = EntryRequest(transactionID: t.id) } } label: { TransactionRow(row: row) }.buttonStyle(.plain)
                    }
                }
                .card()
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle(category?.name ?? L("Без категории"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
