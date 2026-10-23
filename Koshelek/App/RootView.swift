import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var errors = AppErrors.shared

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            if settings.isReplacingData {
                ProgressView().controlSize(.large)
            } else if settings.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-seedDemo"), !settings.hasOnboarded || args.contains("-resetData") {
                DemoData.seed(in: context)
                settings.hasOnboarded = true
            }
            #endif
            if settings.hasOnboarded { RecurringService.generateDue(in: context) }
        }
        .alert("Что-то пошло не так", isPresented: Binding(get: { errors.message != nil }, set: { if !$0 { errors.message = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(errors.message ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, settings.hasOnboarded {
                RecurringService.generateDue(in: context)
                WatchSyncService.shared.schedulePush()
            }
        }
    }
}

enum AppTab: Hashable { case overview, operations, analytics, plans, settings }

@Observable final class Router {
    var entryRequest: EntryRequest?
}

/// Asks the tab bar to show the entry sheet. Holds only the id of the transaction to edit, never the object itself.
struct EntryRequest: Identifiable {
    let id = UUID()
    var transactionID: UUID?
}

/// Resolves the transaction to edit on every render, so the form is never built from an object that was just deleted.
struct EntryHost: View {
    let request: EntryRequest
    @Query private var transactionsQuery: [Transaction]

    var body: some View {
        if let id = request.transactionID {
            if let tx = transactionsQuery.live.first(where: { $0.id == id }) { EntryView(editing: tx) } else { Color.clear }
        } else {
            EntryView(editing: nil)
        }
    }
}

struct MainTabView: View {
    @State private var router = Router()

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("Обзор", systemImage: "square.grid.2x2") }
            OperationsView()
                .tabItem { Label("Операции", systemImage: "list.bullet") }
            AnalyticsView()
                .tabItem { Label("Аналитика", systemImage: "chart.pie") }
            PlansView()
                .tabItem { Label("Планы", systemImage: "target") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .environment(router)
        .sheet(item: $router.entryRequest) { request in
            EntryHost(request: request)
        }
    }
}

/// Floating action button shown over the main screens.
struct FABOverlay: ViewModifier {
    @Environment(Router.self) private var router
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            FAB { router.entryRequest = EntryRequest() }
                .padding(.trailing, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
        }
    }
}

extension View {
    func withFAB() -> some View { modifier(FABOverlay()) }
}
