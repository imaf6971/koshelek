import SwiftUI

/// Watch look: the same warm palette as the phone, always on a dark background.
enum WatchTheme {
    static let accent = Color(hex: 0xE08B6D)
    static let income = Color(hex: 0x8FB07F)
    static let expense = Color(hex: 0xE08B6D)
    static let warning = Color(hex: 0xD9AB57)
    static let card = Color(hex: 0x2B2B29)
    static let textPrimary = Color(hex: 0xF0EEE6)
    static let textSecondary = Color(hex: 0xA6A49B)

    static let bigNumber = Font.system(.title, design: .serif).weight(.semibold)
    static let title = Font.system(.headline, design: .serif)
    static let caption = Font.system(.footnote)

    static func color(_ key: String) -> Color {
        let e = PaletteTable.entries.first { $0.key == key } ?? PaletteTable.entries[0]
        return Color(hex: e.dark)
    }

    static func budgetColor(_ state: Int) -> Color {
        switch state {
        case 2: expense
        case 1: warning
        default: income
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct WatchIcon: View {
    var icon: String
    var colorKey: String
    var body: some View {
        let c = WatchTheme.color(colorKey)
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(c)
            .frame(width: 28, height: 28)
            .background(c.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }
}

struct WatchCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
