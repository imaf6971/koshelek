import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var confirmWipe = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            VStack(spacing: 0) {
            ScreenHeader(title: L("Настройки")).padding(.horizontal, Theme.Spacing.l)
            Form {
                Section("Основное") {
                    NavigationLink {
                        CurrencySettingsView()
                    } label: {
                        LabeledContent("Валюта", value: "\(settings.currency.symbol) \(settings.currency.code == "XXX" ? "" : settings.currency.code)")
                    }
                    Picker("Тема", selection: $settings.theme) {
                        ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) }
                    }
                }.listRowBackground(Theme.Colors.card)
                Section("Справочники") {
                    NavigationLink("Счета") { AccountsView() }
                    NavigationLink("Категории") { CategoriesView() }
                }.listRowBackground(Theme.Colors.card)
                Section {
                    Toggle("Уведомлять о превышении бюджета", isOn: $settings.budgetNotifications)
                } header: {
                    Text("Уведомления")
                } footer: {
                    Text("Локальное уведомление придёт, когда расходы категории превысят месячный бюджет.")
                }.listRowBackground(Theme.Colors.card)
                Section("Данные") {
                    NavigationLink("Экспорт в Excel") { ExportView() }
                    NavigationLink("Резервная копия и восстановление") { BackupView() }
                }.listRowBackground(Theme.Colors.card)
                #if DEBUG
                Section("Разработка (DEBUG)") {
                    Button("Загрузить демо-данные") {
                        DataReplacement.run(settings: settings) { DemoData.seed(in: context); settings.hasOnboarded = true }
                    }
                    Button("Очистить все данные", role: .destructive) { confirmWipe = true }
                }.listRowBackground(Theme.Colors.card)
                #endif
            }
            .scrollContentBackground(.hidden)
            }
            .screenBackground()
            .navigationTitle("Настройки")
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: settings.budgetNotifications) { _, on in
                guard on else { return }
                Task { if await !BudgetNotifier.requestAuthorization() { settings.budgetNotifications = false } }
            }
            .confirmationDialog("Удалить все данные?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Удалить всё", role: .destructive) {
                    DataReplacement.run(settings: settings) {
                        guard BackupService.writeSafetyBackup(in: context, settings: settings, reason: "before-erase") != nil else {
                            AppErrors.shared.report(BackupError.safetyCopyFailed.localizedDescription)
                            return
                        }
                        Store.wipeAll(in: context)
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        settings.resetToDefaults()
                    }
                }
            } message: {
                Text("Все данные и настройки будут стёрты, приложение вернётся к состоянию первого запуска. Перед этим приложение сохранит копию данных в папке «Файлы → Кошелёк → AutoBackups».")
            }
        }
    }
}

struct CurrencySettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var currency = Currency.rub
    @State private var custom = ""
    @State private var useCustom = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                CurrencyChooser(currency: $currency, customSymbol: $custom, useCustom: $useCustom)
                Text("Суммы не пересчитываются: меняется только обозначение валюты.")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle("Валюта")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let p = Currency.presets.first(where: { $0.code == settings.currency.code }) { currency = p } else { useCustom = true; custom = settings.currency.symbol }
        }
        .onChange(of: currency) { _, c in if !useCustom { settings.currency = c } }
        .onChange(of: useCustom) { _, on in
            if on { apply() } else { settings.currency = currency }
        }
        .onChange(of: custom) { _, _ in apply() }
    }

    private func apply() {
        let s = custom.trimmingCharacters(in: .whitespaces)
        if useCustom, !s.isEmpty { settings.currency = Currency(code: "XXX", symbol: s) }
    }
}
