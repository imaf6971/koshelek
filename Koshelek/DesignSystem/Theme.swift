import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Single source of truth for the visual language: colors, fonts, spacing, radii.
enum Theme {
    enum Colors {
        static let background = Color(light: 0xF5F4EE, dark: 0x262624)
        static let card = Color(light: 0xFBFAF6, dark: 0x30302E)
        static let cardRaised = Color(light: 0xEFEDE4, dark: 0x3A3A37)
        static let border = Color(light: 0xE3E0D3, dark: 0x42413D)
        static let textPrimary = Color(light: 0x2E2D2A, dark: 0xF0EEE6)
        static let textSecondary = Color(light: 0x6F6D66, dark: 0xA6A49B)
        static let accent = Color(light: 0xD97757, dark: 0xE08B6D)
        static let onAccent = Color(light: 0xFFFFFF, dark: 0x262624)
        static let income = Color(light: 0x5F7F52, dark: 0x8FB07F)
        static let expense = Color(light: 0xC2603F, dark: 0xE08B6D)
        static let warning = Color(light: 0xC8963E, dark: 0xD9AB57)
        static let uiCard = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x30302E) : UIColor(hex: 0xFBFAF6) }
        static let uiBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x262624) : UIColor(hex: 0xF5F4EE) }
    }

    enum Fonts {
        static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
        static let title = Font.system(.title2, design: .serif).weight(.semibold)
        static let heading = Font.system(.title3, design: .serif).weight(.semibold)
        static let bigNumber = Font.system(.largeTitle, design: .serif).weight(.semibold)
        static let amount = Font.system(.headline, design: .serif)
        static let body = Font.body
        static let caption = Font.footnote
        static let button = Font.system(.headline)
    }

    enum Spacing {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
    }

    /// Muted earthy palette shared by categories, accounts and charts: (light, dark).
    enum Palette {
        static let entries = PaletteTable.entries
        static var keys: [String] { entries.map(\.key) }
        /// Russian color names for VoiceOver.
        static func name(_ key: String) -> String {
            let names = ["clay": "Глина", "sand": "Песок", "olive": "Олива", "slate": "Сланец", "rose": "Пыльная роза", "ochre": "Охра",
                         "sage": "Шалфей", "plum": "Слива", "teal": "Морская волна", "stone": "Камень", "brick": "Кирпич", "moss": "Мох"]
            return names[key] ?? key
        }
        static func color(_ key: String) -> Color {
            let e = entries.first { $0.key == key } ?? entries[0]
            return Color(light: e.light, dark: e.dark)
        }
    }

    /// Curated SF Symbols offered in pickers.
    static let icons: [String] = [
        "fork.knife", "cart", "cup.and.saucer", "bag", "car", "bus", "fuelpump", "tram",
        "house", "bolt", "wifi", "phone", "cross.case", "pills", "tshirt", "sparkles",
        "film", "play.rectangle", "gamecontroller", "music.note", "book", "graduationcap", "gift", "airplane",
        "pawprint", "leaf", "figure.run", "dumbbell", "wrench.and.screwdriver", "sofa", "creditcard", "banknote",
        "briefcase", "percent", "chart.line.uptrend.xyaxis", "building.columns", "arrow.uturn.backward", "star", "heart", "ellipsis.circle",
    ]

    static func configureAppearance() {
        func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(34, .semibold)]
        UINavigationBar.appearance().titleTextAttributes = [.font: serif(17, .semibold)]
    }
}
