import SwiftUI
import Observation

enum ThemeChoice: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("Как в системе")
        case .light: L("Светлая")
        case .dark: L("Тёмная")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// User preferences persisted in UserDefaults.
@Observable final class AppSettings {
    private let defaults: UserDefaults

    var currency: Currency { didSet { save() } }
    var theme: ThemeChoice { didSet { save() } }
    var hasOnboarded: Bool { didSet { save() } }
    var budgetNotifications: Bool { didSet { save() } }

    /// True while all data is being replaced (wipe, demo data, restore); screens are removed so none holds deleted objects.
    var isReplacingData = false

    var money: MoneyFormatter { MoneyFormatter(symbol: currency.symbol) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currency = defaults.data(forKey: "currency").flatMap { try? JSONDecoder().decode(Currency.self, from: $0) } ?? .rub
        theme = defaults.string(forKey: "theme").flatMap(ThemeChoice.init(rawValue:)) ?? .system
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        budgetNotifications = defaults.bool(forKey: "budgetNotifications")
    }

    /// Returns every preference to its first-launch value, so the next screen shown is onboarding.
    func resetToDefaults() {
        currency = .rub
        theme = .system
        budgetNotifications = false
        hasOnboarded = false
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(currency), forKey: "currency")
        defaults.set(theme.rawValue, forKey: "theme")
        defaults.set(hasOnboarded, forKey: "hasOnboarded")
        defaults.set(budgetNotifications, forKey: "budgetNotifications")
    }
}
