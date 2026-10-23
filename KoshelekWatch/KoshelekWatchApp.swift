import SwiftUI

@main
struct KoshelekWatchApp: App {
    @State private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .tint(WatchTheme.accent)
        }
    }
}
