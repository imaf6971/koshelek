import SwiftUI
import SwiftData

@main
struct KoshelekApp: App {
    @State private var settings = AppSettings()
    @State private var container: ModelContainer?
    @State private var storeError = ""

    init() {
        Theme.configureAppearance()
        do { _container = State(initialValue: try AppSchema.makeContainer()) } catch {
            _storeError = State(initialValue: error.localizedDescription)
        }
    }

    private func reload() {
        do { container = try AppSchema.makeContainer(); storeError = "" } catch { storeError = error.localizedDescription }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .environment(settings)
                    .environment(\.locale, Locale(identifier: "ru_RU"))
                    .environment(\.calendar, .app)
                    .preferredColorScheme(settings.theme.colorScheme)
                    .tint(Theme.Colors.accent)
                    .modelContainer(container)
                    .task { WatchSyncService.shared.start(container: container, settings: settings) }
                    .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in WatchSyncService.shared.schedulePush() }
                    .onChange(of: settings.currency) { _, _ in WatchSyncService.shared.schedulePush() }
                    .onChange(of: settings.hasOnboarded) { _, _ in WatchSyncService.shared.schedulePush() }
                    // Saves made while data is being replaced are not pushed, so send the result once it is done.
                    .onChange(of: settings.isReplacingData) { _, busy in if !busy { WatchSyncService.shared.schedulePush() } }
            } else {
                StoreRecoveryView(message: storeError, retry: reload) {
                    StoreRecovery.setAsideStore()
                    settings.hasOnboarded = false
                    reload()
                }
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .tint(Theme.Colors.accent)
            }
        }
    }
}
