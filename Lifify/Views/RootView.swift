import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var holdings: [PortfolioHolding]
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @State private var selectedTab = 0

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
            NavigationStack { DashboardView(isMainTab: true) }
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
        .preferredColorScheme(colorScheme)
        .task {
            await MarketDataService.refresh(holdings: holdings, context: context)
        }
    }
}
