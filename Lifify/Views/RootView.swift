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
                .tabItem { Label(L("Home", "Home"), systemImage: "house") }
                .tag(0)
            NavigationStack { DashboardView(isMainTab: true) }
                .tabItem { Label(L("Finanzen", "Finance"), systemImage: "eurosign.circle") }
                .tag(1)
            NavigationStack { ChallengesView() }
                .tabItem { Label(L("Challenges", "Challenges"), systemImage: "target") }
                .tag(2)
            NavigationStack { HealthView() }
                .tabItem { Label(L("Gesundheit", "Health"), systemImage: "apple.logo") }
                .tag(3)
            NavigationStack { SettingsView() }
                .tabItem { Label(L("Einstellungen", "Settings"), systemImage: "gear") }
                .tag(4)
        }
        .id(language)
        .preferredColorScheme(colorScheme)
        .task {
            await MarketDataService.refresh(holdings: holdings, context: context)
        }
    }
}
