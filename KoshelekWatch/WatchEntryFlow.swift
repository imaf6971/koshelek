import SwiftUI

/// Quick entry: amount on a keypad, then a category; the transaction is sent to the phone right away.
struct WatchEntryFlow: View {
    let snapshot: WatchSnapshot
    var onDone: () -> Void

    @State private var kind = TxKind.expense
    @State private var text = ""

    private var amount: Decimal? { MoneyParser.parse(text).flatMap { $0 > 0 ? $0 : nil } }
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        kindButton(.expense)
                        kindButton(.income)
                    }
                    Text(text.isEmpty ? "0" : text)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Сумма"))
                        .accessibilityValue(Text(text.isEmpty ? "0" : text))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(keys, id: \.self) { k in
                            Button { press(k) } label: {
                                Text(k).font(.system(.title3, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(k == "⌫" ? L("Стереть") : (k == "," ? L("Запятая") : k)))
                        }
                    }
                    NavigationLink {
                        WatchCategoryStep(snapshot: snapshot, kind: kind, amount: amount ?? 0, onDone: onDone)
                    } label: {
                        Text("Далее").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WatchTheme.accent)
                    .disabled(amount == nil)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Новая")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func kindButton(_ k: TxKind) -> some View {
        Button { kind = k } label: {
            Text(k.title).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, minHeight: 28)
                .background(kind == k ? WatchTheme.accent : WatchTheme.card, in: Capsule())
                .foregroundStyle(kind == k ? Color.black : WatchTheme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == k ? .isSelected : [])
    }

    private func press(_ key: String) {
        switch key {
        case "⌫": if !text.isEmpty { text.removeLast() }
        default: if text.count < 9 { text += key }
        }
        text = MoneyParser.sanitize(text)
    }
}

struct WatchCategoryStep: View {
    let snapshot: WatchSnapshot
    let kind: TxKind
    let amount: Decimal
    var onDone: () -> Void

    @Environment(WatchSession.self) private var session
    @State private var accountID: UUID?
    @State private var saved = false

    private var categories: [WatchSnapshot.Category] { kind == .income ? snapshot.incomeCategories : snapshot.expenseCategories }

    var body: some View {
        Group {
            if saved {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(WatchTheme.income)
                    Text("Отправлено на iPhone").font(WatchTheme.title).multilineTextAlignment(.center)
                }
            } else if snapshot.accounts.isEmpty {
                // Every account is archived or deleted: there is nowhere to record the money.
                Text("Нет активных счетов. Добавьте счёт в приложении на iPhone.")
                    .font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary).multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    if snapshot.accounts.count > 1 {
                        Picker("Счёт", selection: Binding(get: { accountID ?? snapshot.accounts.first?.id }, set: { accountID = $0 })) {
                            ForEach(snapshot.accounts) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    ForEach(categories) { c in
                        Button { save(c) } label: {
                            HStack(spacing: 6) {
                                WatchIcon(icon: c.icon, colorKey: c.colorKey)
                                Text(c.name).font(WatchTheme.caption).lineLimit(2)
                            }
                        }
                    }
                    Button { save(nil) } label: { Text("Без категории").font(WatchTheme.caption).foregroundStyle(WatchTheme.textSecondary) }
                }
            }
        }
        .navigationTitle("Категория")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ category: WatchSnapshot.Category?) {
        guard let account = accountID ?? snapshot.accounts.first?.id else { return }
        let entry = WatchEntry(id: UUID(), kind: kind, amount: NSDecimalNumber(decimal: amount).stringValue,
                               accountID: account, categoryID: category?.id, date: Date())
        session.submit(entry)
        saved = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            onDone()
        }
    }
}
