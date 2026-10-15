import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var holdings: [PortfolioHolding]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @StateObject private var workouts = WorkoutStore()
    @StateObject private var financeFilters = FinanceFilterStore()
    @State private var selectedTab = 0
    @State private var financePath = NavigationPath()

    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: theme) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }
                .tabItem { Image(systemName: "house").accessibilityLabel(L("Home", "Home")) }
                .tag(0)
            NavigationStack(path: $financePath) {
                DashboardView(isMainTab: true, path: $financePath)
                    .navigationDestination(for: FinanceRoute.self) { FinanceRouteScreen(route: $0) }
            }
                .tabItem { Image(systemName: "eurosign.circle").accessibilityLabel(L("Finanzen", "Finance")) }
                .tag(1)
            NavigationStack { ChallengesView() }
                .tabItem { Image(systemName: "target").accessibilityLabel(L("Challenges", "Challenges")) }
                .tag(2)
            NavigationStack { HealthView() }
                .tabItem { Image(systemName: "leaf.fill").accessibilityLabel(L("Gesundheit", "Health")) }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Image(systemName: "gear").accessibilityLabel(L("Einstellungen", "Settings")) }
                .tag(4)
        }
        .id(language)
        .environmentObject(workouts)
        .environmentObject(financeFilters)
        .preferredColorScheme(colorScheme)
        .task {
            await MarketDataService.refresh(holdings: holdings, context: context)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await EventKitSyncService().sync(
                context: context,
                existingEvents: calendarEvents,
                existingChallenges: challenges,
                promptForAccess: false
            )
        }
    }
}
