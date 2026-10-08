import SwiftUI

struct RootView: View {
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue

    private var colorScheme: ColorScheme? {
        switch AppTheme(rawValue: theme) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label(L("Übersicht", "Overview"), systemImage: "chart.pie") }
            NavigationStack { TransactionsView() }
                .tabItem { Label(L("Buchungen", "Transactions"), systemImage: "list.bullet.rectangle") }
            NavigationStack { PlanningView() }
                .tabItem { Label(L("Planung", "Planning"), systemImage: "calendar") }
            NavigationStack { OrganizationView() }
                .tabItem { Label(L("Mehr", "More"), systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView() }
                .tabItem { Label(L("Einstellungen", "Settings"), systemImage: "gear") }
        }
        .id(language)
        .preferredColorScheme(colorScheme)
    }
}
