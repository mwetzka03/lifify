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
            glassScreensMatchTheVisiblePages(),
            lightAndDarkPaintsDiffer(),
            fourPalettesKeepLightAndDark(),
            testCategoriesStartCollapsed(),
            briefingDaysSitInOneRow(),
            versionStaysUnderDeveloperMode(),
            advancedEditorSettingsStartClosed(),
            cardsUseTwoColumns(),
            sharedCardRoundsTheEnds(),
            caloriesFollowBodyAndGoal(),
            trainingDayRaisesTheCalorieTarget(),
            fastFoodCostsAndACleanDayPays(),
            pinsStopAtFour(),
            linkedSportCannotBeCheckedByHand(),
            nutritionKeyDepotAndMealsFollowOneRule(),
            emptyCategoryHidesTheCheckCircle(),
            profileLibraryAndCalorieDeficit()
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
            reading: labels.joined(separator: ", "),
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
            reading: "Cents \(Money.cents(from: "19,99") ?? -1), \(labels.joined(separator: ", "))",
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
            reading: names.joined(separator: ", "),
            kind: .unit,
            topic: .screen
        )
    }

    private static func glassScreensMatchTheVisiblePages() -> LififyCheckResult {
        let health = HealthScreen.sectionTitles()
        let settings = SettingsDirectory.rows()
        let expectedSettings = ["person.fill", "gearshape.fill", "eurosign", "flame.fill", "heart.fill", "externaldrive.fill"]
        let passed = health == [L("Training", "Training"), L("Ernährung", "Nutrition")]
            && settings.map(\.symbol) == expectedSettings
            && settings.map(\.title) == [
                L("Nutzereinstellungen", "User settings"),
                L("Allgemein", "General"),
                L("Finanzen", "Finance"),
                L("Herausforderung", "Challenges"),
                L("Gesundheit", "Health"),
                L("Daten", "Data")
            ]
            && AppChrome.glassScreens == ["home", "challenges", "health", "settings", "onboarding", "finance"]
            && AppChrome.glassScreens.contains("finance")
            && AppChrome.version == "0.4.0"
            && NutritionCopy.recognitionPending == L("Die Erkennung ist noch nicht verbunden.", "Recognition is not connected yet.")
        return LififyCheckResult(
            name: "Gesundheit, Einstellungen und Glasflächen zeigen dieselben Titel",
            passed: passed,
            detail: passed ? nil : "\(health.joined(separator: ", ")) / \(AppChrome.version)",
            reading: "\(health.joined(separator: ", ")) / \(AppChrome.version)",
            kind: .integration,
            topic: .screen
        )
    }

    private static func lightAndDarkPaintsDiffer() -> LififyCheckResult {
        let passed = AppLook.modesDiffer()
        let light = AppLook.canvasTop(.light)
        let dark = AppLook.canvasTop(.dark)
        return LififyCheckResult(
            name: "Hell und Dunkel haben eigene Flächen",
            passed: passed,
            detail: passed ? nil : "hell \(light.brightness), dunkel \(dark.brightness)",
            reading: "hell \(light.brightness), dunkel \(dark.brightness)",
            kind: .unit,
            topic: .screen
        )
    }

    private static func fourPalettesKeepLightAndDark() -> LififyCheckResult {
        let labels = AppPalette.allCases.map(\.label)
        let green = AppLook.accent(.light, palette: .green)
        let blue = AppLook.accent(.light, palette: .blue)
        let bordeaux = AppLook.accent(.light, palette: .bordeaux)
        let violet = AppLook.accent(.light, palette: .violet)
        let passed = AppPalette.allCases.allSatisfy(AppLook.modesDiffer(palette:))
            && labels.count == 4
            && (labels[0] == "Grün" || labels[0] == "Green")
            && (labels[1] == "Blau" || labels[1] == "Blue")
            && labels[2] == "Bordeaux"
            && (labels[3] == "Violett" || labels[3] == "Violet")
            && blue.blue > green.blue
            && blue.blue > blue.red
            && bordeaux.red > green.red
            && violet.red > green.red
            && violet.blue > green.blue
            && violet.green < green.green
            && AppLook.canvasTop(.light, palette: .blue) != AppLook.canvasTop(.light, palette: .green)
            && AppLook.canvasTop(.dark, palette: .violet) != AppLook.canvasTop(.dark, palette: .bordeaux)
        return LififyCheckResult(
            name: "Vier Stile haben je eine helle und eine dunkle Fläche",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: ", "),
            reading: labels.joined(separator: ", "),
            kind: .unit,
            topic: .screen
        )
    }

    private static func testCategoriesStartCollapsed() -> LififyCheckResult {
        let sample = [
            LififyCheckResult(name: "Zeta", passed: true, detail: nil, kind: .unit, topic: .shop),
            LififyCheckResult(name: "Mango", passed: false, detail: "fehlt", reading: "fehlt", kind: .integration, topic: .shop),
            LififyCheckResult(name: "Alpha", passed: true, detail: nil, kind: .unit, topic: .shop),
            LififyCheckResult(name: "C", passed: true, detail: nil, kind: .unit, topic: .account),
            LififyCheckResult(name: "D", passed: true, detail: nil, kind: .unit, topic: .navigation)
        ]
        let groups = CheckResultList.groups(from: sample)
        let titles = groups.map(\.topic.title)
        let sorted = titles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let shopNames = groups[2].rows.map(\.name)
        let passed = CheckResultList.startsCollapsed
            && titles == sorted
            && groups.map(\.topic) == [.account, .navigation, .shop]
            && shopNames == ["Alpha", "Zeta", "Mango"]
            && groups[2].summary == "2/3"
            && groups[2].allPassed == false
            && groups[0].summary == "1/1"
        return LififyCheckResult(
            name: "Testkategorien starten eingeklappt",
            passed: passed,
            detail: passed ? nil : groups.map { "\($0.topic.title) \($0.summary)" }.joined(separator: ", "),
            reading: groups.map { "\($0.topic.title) \($0.summary)" }.joined(separator: ", "),
            kind: .integration,
            topic: .screen
        )
    }

    private static func briefingDaysSitInOneRow() -> LififyCheckResult {
        let flags = [2: false]
        let labels = BriefingSchedule.weekdays.map(BriefingWeek.abbreviation)
        let expected = [
            L("Mo", "Mo"), L("Di", "Tu"), L("Mi", "We"), L("Do", "Th"),
            L("Fr", "Fr"), L("Sa", "Sa"), L("So", "Su")
        ]
        let passed = labels == expected
            && BriefingWeek.delivers(master: true, weekday: 2, flags: flags) == false
            && BriefingWeek.delivers(master: true, weekday: 3, flags: flags)
            && BriefingWeek.delivers(master: false, weekday: 3, flags: flags) == false
            && BriefingWeek.isSelected(weekday: 5, flags: [:])
        return LififyCheckResult(
            name: "Die Briefingtage stehen nebeneinander",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: " "),
            reading: labels.joined(separator: " "),
            kind: .unit,
            topic: .challenge
        )
    }

    private static func versionStaysUnderDeveloperMode() -> LififyCheckResult {
        let order = GeneralSettingsOrder.sections
        let passed = order == ["appearance", "briefing", "developer", "version"]
            && order.last == "version"
            && order.dropLast().last == "developer"
        return LififyCheckResult(
            name: "Die Version steht unter dem Entwicklermodus",
            passed: passed,
            detail: passed ? nil : order.joined(separator: ", "),
            reading: order.joined(separator: ", "),
            kind: .unit,
            topic: .developer
        )
    }

    private static func advancedEditorSettingsStartClosed() -> LififyCheckResult {
        let passed = EditorCopy.moreStartsClosed
            && (EditorCopy.moreSettings == "Weitere Einstellungen" || EditorCopy.moreSettings == "More settings")
            && ReminderSyncPreference.isEnabled(for: UUID())
        return LififyCheckResult(
            name: "Weitere Einstellungen starten geschlossen",
            passed: passed,
            detail: passed ? nil : EditorCopy.moreSettings,
            reading: EditorCopy.moreSettings,
            kind: .integration,
            topic: .screen
        )
    }

    private static func cardsUseTwoColumns() -> LififyCheckResult {
        let titles = HealthScreen.sectionTitles()
        let symbols = titles.map(CardBoard.healthSymbol(matching:))
        let duration = ChallengeCardCopy.duration(minutes: 30)
        let bubbles = AccountBubbleBar.titles(accountNames: ["Sparkasse", "Trade Republic"], includesDepot: true)
        let passed = CardBoard.challengeColumnCount == 2
            && CardBoard.challengeColumns().count == 2
            && CardBoard.groupUsesFullWidth
            && CardBoard.singleCardUsesFullWidth
            && CardBoard.healthTileCount == 2
            && CardBoard.healthFiltersShareOneRow
            && titles.count == CardBoard.healthTileCount
            && symbols == ["figure.run", "fork.knife"]
            && CardBoard.toolbarMinHeight == 36
            && CardBoard.toolbarVerticalPadding == 3
            && (ChallengeCreateCopy.abstinence == "Abstinenz anlegen" || ChallengeCreateCopy.abstinence == "Create abstinence")
            && (ChallengeCreateCopy.sport == "Sport anlegen" || ChallengeCreateCopy.sport == "Create sport")
            && (duration == "Dauer 30 min" || duration == "Duration 30 min")
            && bubbles.first == L("Alle Konten", "All accounts")
            && bubbles.last == L("Depot", "Portfolio")
            && CardBoard.spansFullWidth(index: 0, count: 1)
            && !CardBoard.spansFullWidth(index: 0, count: 2)
            && !CardBoard.spansFullWidth(index: 1, count: 2)
            && CardBoard.spansFullWidth(index: 2, count: 3)
            && FactorBoard.streakBubbles() == StreakSettings.thresholds.map { "\($0)×" }
            && CheckStories.expectedLine("1,2").contains("1,2")
            && CheckStories.actualLine("1,2").contains("1,2")
        return LififyCheckResult(
            name: "Challenges und Gesundheit nutzen ein Kartenraster",
            passed: passed,
            detail: passed ? nil : "\(symbols.joined(separator: ", ")) / \(bubbles.joined(separator: ", "))",
            reading: "\(symbols.joined(separator: ", ")) / \(duration) / \(bubbles.joined(separator: ", "))",
            kind: .unit,
            topic: .screen
        )
    }

    private static func sharedCardRoundsTheEnds() -> LififyCheckResult {
        let three = (0..<3).map { ListCardEdge.edge(index: $0, count: 3) }
        let single = ListCardEdge.edge(index: 0, count: 1)
        let passed = three == [.top, .middle, .bottom]
            && single == .single
            && three[0].roundsTop && !three[0].roundsBottom
            && !three[1].roundsTop && !three[1].roundsBottom
            && !three[2].roundsTop && three[2].roundsBottom
            && single.roundsTop && single.roundsBottom
        return LififyCheckResult(
            name: "Die erste und die letzte Zeile runden die Kachel",
            passed: passed,
            detail: passed ? nil : "\(three.count)",
            reading: "top, middle, bottom, single",
            kind: .unit,
            topic: .screen
        )
    }

    private static func caloriesFollowBodyAndGoal() -> LififyCheckResult {
        let lose = NutritionPlan.dayTarget(weightKg: 70, heightCm: 165, age: 30, sex: .female, goal: .loseFat, trained: false)
        let hold = NutritionPlan.dayTarget(weightKg: 70, heightCm: 165, age: 30, sex: .female, goal: .maintain, trained: false)
        let gain = NutritionPlan.dayTarget(weightKg: 80, heightCm: 180, age: 25, sex: .male, goal: .gainMuscle, trained: false)
        let open = NutritionPlan.dayTarget(weightKg: 70, heightCm: 165, age: 30, sex: .unspecified, goal: .maintain, trained: false)
        let missing = NutritionPlan.dayTarget(weightKg: 0, heightCm: 165, age: 30, sex: .female, goal: .loseFat, trained: false)
        let passed = lose == 1448 && hold == 1704 && gain == 2383 && open == 1804 && missing == nil
            && BodyGoal.loseFat.percent == 85
            && BodyGoal.maintain.percent == 100
            && BodyGoal.gainMuscle.percent == 110
            && NutritionPlan.trainingBonus == 250
        let reading = "\(lose ?? 0), \(hold ?? 0), \(gain ?? 0), \(open ?? 0)"
        return LififyCheckResult(
            name: "Die Kalorien folgen Körper und Ziel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    private static func trainingDayRaisesTheCalorieTarget() -> LififyCheckResult {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)) ?? .now
        var session = WorkoutSession(plan: WorkoutPlan(name: "Kraft"))
        session.finishedAt = day
        let other = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let trained = NutritionPlan.trained(on: day, sessions: [session], calendar: calendar)
        let quiet = NutritionPlan.trained(on: other, sessions: [session], calendar: calendar)
        let rest = NutritionPlan.dayTarget(weightKg: 70, heightCm: 165, age: 30, sex: .female, goal: .loseFat, trained: false)
        let active = NutritionPlan.dayTarget(weightKg: 70, heightCm: 165, age: 30, sex: .female, goal: .loseFat, trained: true)
        let meals = [
            MealRecord(dayKey: "2026-11-08", title: "Mittag", source: .manual, status: .confirmed, nutrients: [Nutrient.calories.rawValue: 600, Nutrient.protein.rawValue: 30]),
            MealRecord(dayKey: "2026-11-07", title: "Gestern", source: .manual, status: .confirmed, nutrients: [Nutrient.calories.rawValue: 400])
        ]
        let eaten = NutritionPlan.rounded(.calories, meals: NutritionPlan.onDay("2026-11-08", meals: meals))
        let rows = SettingsDirectory.rows()
        let passed = trained && !quiet
            && rest == 1448
            && active == rest.map { $0 + NutritionPlan.trainingBonus }
            && eaten == 600
            && rows.first?.symbol == "person.fill"
            && rows.first?.title == L("Nutzereinstellungen", "User settings")
            && rows.dropFirst().first?.symbol == "gearshape.fill"
            && !DepotLoad.showsBoard(ready: false)
            && DepotLoad.showsBoard(ready: true)
        let reading = "\(active ?? 0), \(eaten), user"
        return LififyCheckResult(
            name: "Ein Trainingstag hebt das Kalorienziel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    private static func fastFoodCostsAndACleanDayPays() -> LififyCheckResult {
        let clean = MealScore.coins(eaten: 1000, target: 1400, kinds: [.whole, .balanced])
        let fast = MealScore.coins(eaten: 1000, target: 1400, kinds: [.fastFood])
        let over = MealScore.coins(eaten: 2000, target: 1400, kinds: [.whole])
        let empty = MealScore.coins(eaten: 0, target: 1400, kinds: [])
        let passed = MealScore.fastFoodPrice == 25
            && MealScore.buysFastFood([.balanced, .fastFood])
            && !MealScore.buysFastFood([.whole])
            && clean == 30
            && fast == 20
            && over == 0
            && empty == 0
            && MealScore.points(for: .fastFood) < 0
            && MealScore.points(for: .whole) > 0
        let reading = "\(MealScore.fastFoodPrice), \(clean), \(fast), \(over)"
        return LififyCheckResult(
            name: "Fast Food kostet Coins und ein sauberer Tag zahlt",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    private static func pinsStopAtFour() -> LififyCheckResult {
        let ids = (0..<4).map { _ in UUID() }
        let held = ChallengePinStore.kept(ids, adding: UUID())
        let grew = ChallengePinStore.kept(Array(ids.prefix(3)), adding: UUID())
        let dropped = ChallengePinStore.removed(ids, ids[0])
        let passed = held.count == ChallengePinStore.limit
            && held == ids
            && grew.count == 4
            && dropped.count == 3
            && !dropped.contains(ids[0])
        let reading = "\(held.count), \(dropped.count)"
        return LififyCheckResult(
            name: "Höchstens vier Challenges bleiben angepinnt",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    private static func linkedSportCannotBeCheckedByHand() -> LififyCheckResult {
        let sport = ChallengeCheckoff.allowsHand(category: .sport, linkedWorkouts: 1)
        let open = ChallengeCheckoff.allowsHand(category: .sport, linkedWorkouts: 0)
        let other = ChallengeCheckoff.allowsHand(category: .other, linkedWorkouts: 1)
        let passed = !sport && open && other
        let reading = "sport, other"
        return LififyCheckResult(
            name: "Eine gekoppelte Sport-Challenge lässt sich nicht abhaken",
            passed: passed,
            detail: passed ? nil : "\(sport), \(open), \(other)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    private static func nutritionKeyDepotAndMealsFollowOneRule() -> LififyCheckResult {
        let passed = !MealRecognition.connected(hasKey: false)
            && MealRecognition.connected(hasKey: true)
            && MealRecognition.model == "gemini-2.5-flash"
            && !DepotLoad.shouldSpin(ready: true, opened: true)
            && DepotLoad.shouldSpin(ready: false, opened: true)
            && DepotLoad.showsBoard(ready: true)
            && MealScore.fastFoodPrice == 25
            && ChallengePinStore.limit == 4
            && NutritionLedger.challengeMark == "nutrition:calories"
            && MealKind.resolved("fast_food") == .fastFood
            && MealKind.fastFood.label == L("Fast Food", "Fast food")
        let reading = "ready, 25, 4"
        return LififyCheckResult(
            name: "Schlüssel, Depot und Ernährung folgen derselben Regel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    private static func emptyCategoryHidesTheCheckCircle() -> LififyCheckResult {
        let hidden = !ChallengeBoard.showsCategory(unpinned: 0)
        let shown = ChallengeBoard.showsCategory(unpinned: 1)
        let noCircle = !ChallengeBoard.showsCheckCircle(allowsHand: false)
        let circle = ChallengeBoard.showsCheckCircle(allowsHand: true)
        let passed = hidden && shown && noCircle && circle
        let reading = "0, weg"
        return LififyCheckResult(
            name: "Eine leere Kategorie zeigt keinen Haken",
            passed: passed,
            detail: passed ? nil : "\(hidden), \(shown), \(noCircle), \(circle)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    private static func profileLibraryAndCalorieDeficit() -> LififyCheckResult {
        let rows = SettingsDirectory.rows()
        let passed = rows.first?.symbol == "person.fill"
            && rows.first?.title == L("Nutzereinstellungen", "User settings")
            && rows.dropFirst().first?.symbol == "gearshape.fill"
            && !MealCapture.keepsInLibrary(false)
            && MealCapture.keepsInLibrary(true)
            && NutritionCopy.calorieChallenge == L("Kaloriendefizit", "Calorie deficit")
            && ChallengeCreateMenu.abstinence == L("Abstinenz-Challenge", "Abstinence challenge")
            && ChallengeCreateMenu.sport == L("Sport-Challenge", "Sport challenge")
            && ChallengeCreateMenu.other == L("Sonstige Challenge", "Other challenge")
            && ChallengeCreateMenu.group == L("Gruppe", "Group")
            && ChallengeCreateMenu.labels.count == 4
        let reading = "Profil, aus, Kaloriendefizit"
        return LififyCheckResult(
            name: "Profil, Galerie und Kaloriendefizit",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }
}
