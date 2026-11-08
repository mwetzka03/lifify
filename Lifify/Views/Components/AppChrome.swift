import SwiftUI

/// Shared type scale for every screen except Finance.
enum AppTextRole: String, Equatable, CaseIterable {
    case screenTitle
    case section
    case row
    case caption
    case value
}

enum AppChrome {
    static let version = "0.4.0"

    /// Screens that use the painted canvas. Finance keeps its own card arrangement.
    static let glassScreens = ["home", "challenges", "health", "settings", "onboarding", "finance"]

    static func font(_ role: AppTextRole) -> Font {
        switch role {
        case .screenTitle: .title2.weight(.semibold)
        case .section: .headline
        case .row: .body
        case .caption: .caption
        case .value: .title3.weight(.semibold)
        }
    }
}

struct AppTab: Equatable {
    var title: String
    var symbol: String
    var tag: Int
}

enum AppTabs {
    static func items() -> [AppTab] {
        [
            AppTab(title: L("Home", "Home"), symbol: "house", tag: 0),
            AppTab(title: L("Finanzen", "Finance"), symbol: "eurosign.circle", tag: 1),
            AppTab(title: L("Challenges", "Challenges"), symbol: "target", tag: 2),
            AppTab(title: L("Gesundheit", "Health"), symbol: "leaf.fill", tag: 3),
            AppTab(title: L("Einstellungen", "Settings"), symbol: "gear", tag: 4)
        ]
    }
}

enum HealthScreen {
    static func sectionTitles() -> [String] {
        [L("Training", "Training"), L("Abstinenz", "Abstinence"), L("Ernährung", "Nutrition")]
    }

    static var nutritionNote: String { L("Noch nicht verfügbar", "Not available yet") }
}

struct SettingsDirectoryRow: Identifiable, Equatable {
    var title: String
    var symbol: String
    var id: String { symbol }
}

enum SettingsDirectory {
    static func rows() -> [SettingsDirectoryRow] {
        [
            SettingsDirectoryRow(title: L("Allgemein", "General"), symbol: "gearshape.fill"),
            SettingsDirectoryRow(title: L("Finanzen", "Finance"), symbol: "eurosign"),
            SettingsDirectoryRow(title: L("Herausforderung", "Challenges"), symbol: "flame.fill"),
            SettingsDirectoryRow(title: L("Gesundheit", "Health"), symbol: "heart.fill"),
            SettingsDirectoryRow(title: L("Daten", "Data"), symbol: "externaldrive.fill")
        ]
    }
}
