import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var currency = Currency.rub
    @State private var customSymbol = ""
    @State private var useCustom = false
    @State private var accountName = L("Карта")
    @State private var balanceText = ""

    private var effectiveCurrency: Currency {
        let s = customSymbol.trimmingCharacters(in: .whitespaces)
        return useCustom && !s.isEmpty ? Currency(code: "XXX", symbol: s) : currency
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Кошелёк").font(Theme.Fonts.display)
                    Text("Спокойный учёт личных финансов. Все данные хранятся только на этом устройстве.")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, Theme.Spacing.xxl)

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Валюта").font(Theme.Fonts.heading)
                    CurrencyChooser(currency: $currency, customSymbol: $customSymbol, useCustom: $useCustom)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Первый счёт").font(Theme.Fonts.heading)
                    VStack(spacing: 0) {
                        TextField("Название", text: $accountName).padding(Theme.Spacing.l)
                        Divider().overlay(Theme.Colors.border)
                        TextField("Текущий баланс", text: $balanceText).keyboardType(.decimalPad).padding(Theme.Spacing.l)
                    }
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.Colors.border))
                }

                #if DEBUG
                Button("Заполнить демо-данными (DEBUG)") {
                    settings.currency = effectiveCurrency
                    DemoData.seed(in: context)
                    settings.hasOnboarded = true
                }
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                #endif
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Начать", action: start)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(accountName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Colors.background)
        }
    }

    private func start() {
        settings.currency = effectiveCurrency
        DefaultCategories.ensure(in: context)
        context.insert(Account(name: accountName.trimmingCharacters(in: .whitespaces), initialBalance: MoneyParser.parse(balanceText) ?? 0))
        context.saveOrReport()
        settings.hasOnboarded = true
    }
}

struct CurrencyChooser: View {
    @Binding var currency: Currency
    @Binding var customSymbol: String
    @Binding var useCustom: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            FlowLayout(spacing: Theme.Spacing.s) {
                ForEach(Currency.presets) { c in
                    Button { currency = c; useCustom = false } label: {
                        Text("\(c.symbol) \(c.code)").chip(selected: !useCustom && currency == c)
                    }
                    .buttonStyle(.plain)
                }
                Button { useCustom = true } label: { Text("Другая").chip(selected: useCustom) }.buttonStyle(.plain)
            }
            if useCustom {
                TextField("Символ валюты, например ֏", text: $customSymbol)
                    .padding(Theme.Spacing.m)
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.Colors.border))
            }
        }
    }
}

/// Wraps children onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in result.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        var points: [CGPoint] = []
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
