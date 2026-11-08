import Foundation

/// Checks for the booking picker and the screens outside Finance.
/// They read labels and catalog data only and do not write the user's data.
@MainActor
enum LififyFeatureChecks {
    static func run() -> [LififyCheckResult] {
        [
            manualCategoriesStayOutOfThePicker(),
            manualPickerMatchesTheAmountField(),
            symbolChoicesIncludeLeafAndCigarette(),
            glassScreensMatchTheVisiblePages()
        ]
    }

    private static func manualCategoriesStayOutOfThePicker() -> LififyCheckResult {
        let locked: Set<BookingCategory> = [.portfolioBuy, .portfolioSale, .savingsPlan]
        let offered = Set(BookingCategory.manualChoices)
        let labels = BookingCategory.manualChoices.map(\.label)
        let lockedLabels = locked.map(\.label)
        let passed = locked.isDisjoint(with: offered)
            && labels.allSatisfy { !$0.isEmpty }
            && Set(labels).isDisjoint(with: lockedLabels)
        return LififyCheckResult(
            name: "Manuelle Buchung blendet Depot und Sparplan aus",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: ", "),
            kind: .unit,
            topic: .finance
        )
    }

    private static func manualPickerMatchesTheAmountField() -> LififyCheckResult {
        let labels = BookingCategory.manualChoices.map(\.label)
        let blocked = [
            BookingCategory.portfolioBuy.label,
            BookingCategory.portfolioSale.label,
            BookingCategory.savingsPlan.label
        ]
        let cents = Money.cents(from: "19,99") == 1999 && Money.cents(from: "1.250,50") == 125050
        let passed = cents && blocked.allSatisfy { !labels.contains($0) } && labels.count == 7
        return LififyCheckResult(
            name: "Buchungsfeld und Betrag nutzen dieselben Kategorien",
            passed: passed,
            detail: passed ? nil : "Cents \(Money.cents(from: "19,99") ?? -1), \(labels.joined(separator: ", "))",
            kind: .integration,
            topic: .finance
        )
    }

    private static func symbolChoicesIncludeLeafAndCigarette() -> LififyCheckResult {
        let choices = SymbolCatalog.choices()
        let names = choices.map(\.name)
        let leaf = choices.first { $0.name == "symbol.hemp-leaf" }
        let cigarette = choices.first { $0.name == "symbol.cigarette" }
        let passed = Set(names).count == names.count
            && leaf?.title == L("Hanfblatt", "Hemp leaf")
            && cigarette?.title == L("Zigarette", "Cigarette")
            && AppSymbol.assetName(in: "symbol.hemp-leaf") == "hemp-leaf"
            && AppSymbol.assetName(in: "symbol.cigarette") == "cigarette"
            && AppSymbol.assetName(in: "leaf") == nil
        return LififyCheckResult(
            name: "Die Symbolauswahl enthält Hanfblatt und Zigarette",
            passed: passed,
            detail: passed ? nil : names.joined(separator: ", "),
            kind: .unit,
            topic: .screen
        )
    }

    private static func glassScreensMatchTheVisiblePages() -> LififyCheckResult {
        let health = HealthScreen.sectionTitles()
        let settings = SettingsDirectory.rows()
        let expectedSettings = ["gearshape.fill", "eurosign", "flame.fill", "heart.fill", "externaldrive.fill"]
        let passed = health == [L("Training", "Training"), L("Abstinenz", "Abstinence"), L("Ernährung", "Nutrition")]
            && settings.map(\.symbol) == expectedSettings
            && settings.map(\.title) == [
                L("Allgemein", "General"),
                L("Finanzen", "Finance"),
                L("Herausforderung", "Challenges"),
                L("Gesundheit", "Health"),
                L("Daten", "Data")
            ]
            && AppChrome.glassScreens == ["home", "challenges", "health", "settings", "onboarding"]
            && !AppChrome.glassScreens.contains("finance")
            && AppChrome.version == "0.4.0"
            && HealthScreen.nutritionNote == L("Noch nicht verfügbar", "Not available yet")
        return LififyCheckResult(
            name: "Gesundheit, Einstellungen und Glasflächen zeigen dieselben Titel",
            passed: passed,
            detail: passed ? nil : "\(health.joined(separator: ", ")) / \(AppChrome.version)",
            kind: .integration,
            topic: .screen
        )
    }
}
