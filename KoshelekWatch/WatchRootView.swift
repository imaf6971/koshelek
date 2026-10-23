import SwiftUI

struct WatchRootView: View {
    @Environment(WatchSession.self) private var session

    var body: some View {
        NavigationStack {
            if let snapshot = session.snapshot {
                TabView {
                    SummaryPage(snapshot: snapshot)
                    BudgetsPage(snapshot: snapshot)
                    RecentPage(snapshot: snapshot)
                }
                .tabViewStyle(.verticalPage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone.and.arrow.forward").font(.title2).foregroundStyle(WatchTheme.textSecondary)
                    Text("Откройте «Кошелёк» на iPhone")
                        .font(WatchTheme.title).multilineTextAlignment(.center)
                    Text("Данные появятся здесь после первой синхронизации.")
                        .font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        #if DEBUG
        .task {
            // Test aid: -autoEntry sends one expense to the phone at launch, without tapping through the keypad.
            guard ProcessInfo.processInfo.arguments.contains("-autoEntry"), let s = session.snapshot, let account = s.accounts.first else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            session.submit(WatchEntry(id: UUID(), kind: .expense, amount: "50", accountID: account.id,
                                      categoryID: s.expenseCategories.first?.id, date: Date()))
        }
        #endif
    }
}

struct SummaryPage: View {
    let snapshot: WatchSnapshot
    @Environment(WatchSession.self) private var session
    @State private var showEntry = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.monthTitle).font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary)
                    Text(snapshot.totalBalance).font(WatchTheme.bigNumber).minimumScaleFactor(0.5).lineLimit(1)
                }
                HStack(spacing: 8) {
                    stat(L("Доходы"), snapshot.monthIncome, WatchTheme.income)
                    stat(L("Расходы"), snapshot.monthExpense, WatchTheme.expense)
                }
                WatchCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("К концу месяца").font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary)
                        Text(snapshot.forecast).font(WatchTheme.title).minimumScaleFactor(0.6).lineLimit(1)
                        Text(snapshot.forecastNote).font(.system(size: 11)).foregroundStyle(WatchTheme.textSecondary)
                    }
                }
                Button { showEntry = true } label: {
                    Label("Добавить", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchTheme.accent)
                ForEach(session.failed, id: \.self) { text in
                    Text(text).font(.system(size: 11)).foregroundStyle(WatchTheme.expense)
                }
                if !session.failed.isEmpty {
                    Button("Скрыть") { session.dismissFailures() }.font(.system(size: 12))
                }
                if !session.pending.isEmpty {
                    Text(LF("Ждёт отправки: %d", session.pending.count))
                        .font(.system(size: 11)).foregroundStyle(WatchTheme.warning)
                }
                ForEach(snapshot.accounts) { a in
                    HStack {
                        Text(a.name).font(WatchTheme.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(a.balance).font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showEntry) { WatchEntryFlow(snapshot: snapshot) { showEntry = false } }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11)).foregroundStyle(WatchTheme.textSecondary)
            Text(value).font(.system(.footnote, design: .serif).weight(.semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetsPage: View {
    let snapshot: WatchSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Бюджеты").font(WatchTheme.title)
                if snapshot.budgets.isEmpty {
                    Text("Бюджетов нет. Добавьте их в приложении на iPhone.")
                        .font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary)
                }
                ForEach(snapshot.budgets) { b in
                    WatchCard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                WatchIcon(icon: b.icon, colorKey: b.colorKey)
                                Text(b.name).font(WatchTheme.caption).lineLimit(1)
                            }
                            ProgressView(value: min(b.ratio, 1)).tint(WatchTheme.budgetColor(b.state))
                            Text("\(b.spent) / \(b.limit)")
                                .font(.system(size: 11)).foregroundStyle(b.state == 0 ? WatchTheme.textSecondary : WatchTheme.budgetColor(b.state))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text(PercentFormatter.string(b.ratio)))
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct RecentPage: View {
    let snapshot: WatchSnapshot
    @Environment(WatchSession.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Операции").font(WatchTheme.title)
                if snapshot.recent.isEmpty && session.pending.isEmpty {
                    Text("Пока нет операций.").font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary)
                }
                ForEach(snapshot.recent) { t in
                    HStack(spacing: 6) {
                        WatchIcon(icon: t.icon, colorKey: t.colorKey)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.title).font(WatchTheme.caption).lineLimit(1)
                            Text(t.amount).font(.system(.footnote, design: .serif).weight(.semibold))
                                .foregroundStyle(t.kind == .income ? WatchTheme.income : WatchTheme.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
