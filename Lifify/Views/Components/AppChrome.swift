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

/// Card layout for Challenges and Health. One challenge in a section uses the full width.
enum CardBoard {
    static let challengeColumnCount = 2
    static let groupUsesFullWidth = true
    static let singleCardUsesFullWidth = true
    static let healthTileCount = 3
    static let healthFiltersShareOneRow = true

    static func challengeColumns() -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
            count: challengeColumnCount
        )
    }

    static func healthSymbol(matching title: String) -> String {
        let titles = HealthScreen.sectionTitles()
        if titles.count > 1, title == titles[1] { return "lungs.fill" }
        if titles.count > 2, title == titles[2] { return "fork.knife" }
        return "figure.run"
    }
}

enum ChallengeCardCopy {
    static func duration(minutes: Int) -> String {
        L("Dauer \(minutes) min", "Duration \(minutes) min")
    }
}

enum AccountBubbleBar {
    static func titles(accountNames: [String], includesDepot: Bool) -> [String] {
        var titles = [L("Alle Konten", "All accounts")]
        titles.append(contentsOf: accountNames)
        if includesDepot { titles.append(L("Depot", "Portfolio")) }
        return titles
    }
}

enum FactorBoard {
    static func streakBubbles() -> [String] {
        StreakSettings.thresholds.map { "\($0)×" }
    }
}

struct ChoiceBubble: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : AppSurface.card, in: Capsule())
    }
}

/// Wraps bubbles onto as many as fit, then shares the leftover width across the gaps in that row.
struct EvenBubbleRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let offered = proposal.width ?? 0
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        let widest = natural.max() ?? 0
        let width = offered > 0 ? offered : widest
        let lines = lines(in: max(width, 1), subviews: subviews)
        let height = lines.reduce(CGFloat.zero) { $0 + $1.height }
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = lines(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            let gaps = max(line.indexes.count - 1, 1)
            let extra = line.indexes.count > 1 ? max(bounds.width - line.used, 0) / CGFloat(gaps) : 0
            var x = bounds.minX
            for index in line.indexes {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing + extra
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indexes: [Int] = []
        var used: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(in width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = line.indexes.isEmpty ? size.width : line.used + spacing + size.width
            if !line.indexes.isEmpty, next > width + 0.5 {
                lines.append(line)
                line = Line(indexes: [index], used: size.width, height: size.height)
            } else {
                line.indexes.append(index)
                line.used = next
                line.height = max(line.height, size.height)
            }
        }
        if !line.indexes.isEmpty { lines.append(line) }
        return lines
    }
}

struct MoreSettingsToggle: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack {
                Text(EditorCopy.moreSettings)
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
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
