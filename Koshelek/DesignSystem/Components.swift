import SwiftUI

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.l).stroke(Theme.Colors.border, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = Theme.Spacing.l) -> some View { modifier(CardModifier(padding: padding)) }
    func screenBackground() -> some View { background(Theme.Colors.background.ignoresSafeArea()) }
    func listStyleWarm() -> some View {
        scrollContentBackground(.hidden).background(Theme.Colors.background.ignoresSafeArea())
    }
}

/// Lays children out in a row, or stacked once Dynamic Type reaches accessibility sizes.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var spacing: CGFloat = Theme.Spacing.l
    @ViewBuilder var content: Content
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: spacing) { content }
        }
    }
}

/// Leading and trailing content side by side, stacked at accessibility Dynamic Type sizes.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { leading; trailing }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: Theme.Spacing.m) { leading; Spacer(minLength: Theme.Spacing.s); trailing }
        }
    }
}

/// Large screen title in the serif face, used instead of the system navigation bar title to save vertical space.
struct ScreenHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, Theme.Spacing.s)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Round header button (filter, add) in the accent color.
struct HeaderButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.card, in: Circle())
                .overlay(Circle().stroke(Theme.Colors.border, lineWidth: 1))
        }
        .accessibilityLabel(Text(label))
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String?
    var action: (() -> Void)?
    var body: some View {
        HStack {
            Text(title).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.accent)
            }
        }
    }
}

struct EmptyStateView: View {
    var icon: String
    var title: String
    var hint: String
    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(title).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary).multilineTextAlignment(.center)
            Text(hint).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}

struct IconBadge: View {
    var icon: String
    var colorKey: String
    var size: CGFloat = 36
    var body: some View {
        let c = Theme.Palette.color(colorKey)
        Image(systemName: icon)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(c)
            .frame(width: size, height: size)
            .background(c.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ProgressBar: View {
    var value: Double
    var color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.cardRaised)
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.25), value: value)
        .accessibilityHidden(true)
    }
}

struct FAB: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.Colors.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.Colors.accent, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .accessibilityLabel(Text("Добавить операцию"))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.button)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .foregroundStyle(isEnabled ? Theme.Colors.onAccent : Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.l)
            .background(isEnabled ? Theme.Colors.accent : Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct ChipStyle: ViewModifier {
    var selected: Bool
    func body(content: Content) -> some View {
        content
            .font(Theme.Fonts.caption.weight(.medium))
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .background(selected ? Theme.Colors.accent : Theme.Colors.card, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.Colors.border, lineWidth: 1))
    }
}

extension View {
    func chip(selected: Bool) -> some View { modifier(ChipStyle(selected: selected)) }
}

/// Grid for choosing an icon and color.
struct IconColorPicker: View {
    @Binding var icon: String
    @Binding var colorKey: String
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 8)]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Theme.Palette.keys, id: \.self) { k in
                    Button { colorKey = k } label: {
                        Circle().fill(Theme.Palette.color(k)).frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Theme.Colors.textPrimary, lineWidth: colorKey == k ? 2.5 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(Theme.Palette.name(k)))
                    .accessibilityAddTraits(colorKey == k ? .isSelected : [])
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Theme.icons, id: \.self) { i in
                    Button { icon = i } label: {
                        Image(systemName: i).font(.system(size: 18))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(icon == i ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
                            .background(icon == i ? Theme.Palette.color(colorKey) : Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Значок"))
                    .accessibilityAddTraits(icon == i ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}
