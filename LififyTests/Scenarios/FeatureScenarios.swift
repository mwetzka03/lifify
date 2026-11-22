import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
@testable import Lifify

/// Checks for the booking picker and the screens outside Finance.
/// They read labels and catalog data only and do not write the user's data.
@MainActor
enum FeatureScenarios {
    static func manualCategoriesStayOutOfThePicker() -> RuleScenario {
        let locked: Set<BookingCategory> = [.portfolioBuy, .portfolioSale, .savingsPlan]
        let offered = Set(BookingCategory.manualChoices)
        let labels = BookingCategory.manualChoices.map(\.label)
        let lockedLabels = locked.map(\.label)
        let passed = locked.isDisjoint(with: offered)
            && labels.allSatisfy { !$0.isEmpty }
            && Set(labels).isDisjoint(with: lockedLabels)
        return RuleScenario(
            name: "Manuelle Buchung blendet Depot und Sparplan aus",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: ", "),
            reading: labels.joined(separator: ", "),
            kind: .unit,
            topic: .finance
        )
    }

    static func manualPickerMatchesTheAmountField() -> RuleScenario {
        let labels = BookingCategory.manualChoices.map(\.label)
        let blocked = [
            BookingCategory.portfolioBuy.label,
            BookingCategory.portfolioSale.label,
            BookingCategory.savingsPlan.label
        ]
        let cents = Money.cents(from: "19,99") == 1999 && Money.cents(from: "1.250,50") == 125050
        let passed = cents && blocked.allSatisfy { !labels.contains($0) } && labels.count == 9
        return RuleScenario(
            name: "Buchungsfeld und Betrag nutzen dieselben Kategorien",
            passed: passed,
            detail: passed ? nil : "Cents \(Money.cents(from: "19,99") ?? -1), \(labels.joined(separator: ", "))",
            reading: "Cents \(Money.cents(from: "19,99") ?? -1), \(labels.joined(separator: ", "))",
            kind: .integration,
            topic: .finance
        )
    }

    static func symbolChoicesIncludeLeafAndCigarette() -> RuleScenario {
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
        return RuleScenario(
            name: "Die Symbolauswahl enthält Hanfblatt und Zigarette",
            passed: passed,
            detail: passed ? nil : names.joined(separator: ", "),
            reading: names.joined(separator: ", "),
            kind: .unit,
            topic: .screen
        )
    }

    static func lightAndDarkPaintsDiffer() -> RuleScenario {
        let passed = AppLook.modesDiffer()
        let light = AppLook.canvasTop(.light)
        let dark = AppLook.canvasTop(.dark)
        return RuleScenario(
            name: "Hell und Dunkel haben eigene Flächen",
            passed: passed,
            detail: passed ? nil : "hell \(light.brightness), dunkel \(dark.brightness)",
            reading: "hell \(light.brightness), dunkel \(dark.brightness)",
            kind: .unit,
            topic: .screen
        )
    }

    static func fourPalettesKeepLightAndDark() -> RuleScenario {
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
        return RuleScenario(
            name: "Vier Stile haben je eine helle und eine dunkle Fläche",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: ", "),
            reading: labels.joined(separator: ", "),
            kind: .unit,
            topic: .screen
        )
    }

    static func briefingDaysSitInOneRow() -> RuleScenario {
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
        return RuleScenario(
            name: "Die Briefingtage stehen nebeneinander",
            passed: passed,
            detail: passed ? nil : labels.joined(separator: " "),
            reading: labels.joined(separator: " "),
            kind: .unit,
            topic: .challenge
        )
    }

    static func advancedEditorSettingsStartClosed() -> RuleScenario {
        let passed = EditorCopy.moreStartsClosed
            && (EditorCopy.moreSettings == "Weitere Einstellungen" || EditorCopy.moreSettings == "More settings")
            && ReminderSyncPreference.isEnabled(for: UUID())
        return RuleScenario(
            name: "Weitere Einstellungen starten geschlossen",
            passed: passed,
            detail: passed ? nil : EditorCopy.moreSettings,
            reading: EditorCopy.moreSettings,
            kind: .integration,
            topic: .screen
        )
    }

    static func cardsUseTwoColumns() -> RuleScenario {
        let titles = HealthScreen.sectionTitles()
        let symbols = titles.map(CardBoard.healthSymbol(matching:))
        let duration = ChallengeCardCopy.scheduleLine(recurrence: L("Einmalig", "Once"), minutes: 30)
        let bubbles = AccountBubbleBar.titles(accountNames: ["Sparkasse", "Trade Republic"], includesDepot: true)
        let passed = CardBoard.challengeColumnCount == 2
            && CardBoard.challengeColumns().count == 2
            && CardBoard.singleCardUsesFullWidth
            && CardBoard.healthFiltersShareOneRow
            && titles.count == 2
            && symbols == ["figure.run", "fork.knife"]
            && CardBoard.toolbarMinHeight == 36
            && CardBoard.toolbarVerticalPadding == 3
            && (ChallengeCreateCopy.abstinence == "Abstinenz anlegen" || ChallengeCreateCopy.abstinence == "Create abstinence")
            && (ChallengeCreateCopy.sport == "Sport anlegen" || ChallengeCreateCopy.sport == "Create sport")
            && (duration == "Einmalig - 30 Minuten" || duration == "Once - 30 minutes")
            && bubbles.first == L("Alle Konten", "All accounts")
            && bubbles.last == L("Depot", "Portfolio")
            && CardBoard.spansFullWidth(index: 0, count: 1)
            && !CardBoard.spansFullWidth(index: 0, count: 2)
            && !CardBoard.spansFullWidth(index: 1, count: 2)
            && CardBoard.spansFullWidth(index: 2, count: 3)
            && FactorBoard.streakBubbles() == StreakSettings.thresholds.map { "\($0)×" }
        return RuleScenario(
            name: "Challenges und Gesundheit nutzen ein Kartenraster",
            passed: passed,
            detail: passed ? nil : "\(symbols.joined(separator: ", ")) / \(bubbles.joined(separator: ", "))",
            reading: "\(symbols.joined(separator: ", ")) / \(duration) / \(bubbles.joined(separator: ", "))",
            kind: .unit,
            topic: .screen
        )
    }

    static func sharedCardRoundsTheEnds() -> RuleScenario {
        let three = (0..<3).map { ListCardEdge.edge(index: $0, count: 3) }
        let single = ListCardEdge.edge(index: 0, count: 1)
        let passed = three == [.top, .middle, .bottom]
            && single == .single
            && three[0].roundsTop && !three[0].roundsBottom
            && !three[1].roundsTop && !three[1].roundsBottom
            && !three[2].roundsTop && three[2].roundsBottom
            && single.roundsTop && single.roundsBottom
        return RuleScenario(
            name: "Die erste und die letzte Zeile runden die Kachel",
            passed: passed,
            detail: passed ? nil : "\(three.count)",
            reading: "top, middle, bottom, single",
            kind: .unit,
            topic: .screen
        )
    }

    static func caloriesFollowBodyAndGoal() -> RuleScenario {
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
        return RuleScenario(
            name: "Die Kalorien folgen Körper und Ziel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func trainingDayRaisesTheCalorieTarget() -> RuleScenario {
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
        return RuleScenario(
            name: "Ein Trainingstag hebt das Kalorienziel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    static func fastFoodCostsAndACleanDayPays() -> RuleScenario {
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
        return RuleScenario(
            name: "Fast Food kostet Coins und ein sauberer Tag zahlt",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func pinsStopAtFour() -> RuleScenario {
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
        return RuleScenario(
            name: "Höchstens vier Challenges bleiben angepinnt",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func linkedSportCannotBeCheckedByHand() -> RuleScenario {
        let sport = ChallengeCheckoff.allowsHand(category: .sport, linkedWorkouts: 1)
        let open = ChallengeCheckoff.allowsHand(category: .sport, linkedWorkouts: 0)
        let other = ChallengeCheckoff.allowsHand(category: .other, linkedWorkouts: 1)
        let passed = !sport && open && other
        let reading = "sport, other"
        return RuleScenario(
            name: "Eine gekoppelte Sport-Challenge lässt sich nicht abhaken",
            passed: passed,
            detail: passed ? nil : "\(sport), \(open), \(other)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func nutritionKeyDepotAndMealsFollowOneRule() -> RuleScenario {
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
        return RuleScenario(
            name: "Schlüssel, Depot und Ernährung folgen derselben Regel",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    static func emptyCategoryHidesTheCheckCircle() -> RuleScenario {
        let hidden = !ChallengeBoard.showsCategory(unpinned: 0)
        let shown = ChallengeBoard.showsCategory(unpinned: 1)
        let noCircle = !ChallengeBoard.showsCheckCircle(allowsHand: false)
        let circle = ChallengeBoard.showsCheckCircle(allowsHand: true)
        let passed = hidden && shown && noCircle && circle
        let reading = "0, weg"
        return RuleScenario(
            name: "Eine leere Kategorie zeigt keinen Haken",
            passed: passed,
            detail: passed ? nil : "\(hidden), \(shown), \(noCircle), \(circle)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func profileLibraryAndCalorieDeficit() -> RuleScenario {
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
        return RuleScenario(
            name: "Profil, Galerie und Kaloriendefizit",
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    static func goalDecidesNutritionCoins() -> RuleScenario {
        let over = MealScore.coins(eaten: 2000, target: 1400, kinds: [.hearty], goal: .loseFat)
        let underMuscle = MealScore.coins(eaten: 1000, target: 1400, kinds: [.hearty], goal: .gainMuscle)
        let reached = MealScore.coins(eaten: 1400, target: 1400, kinds: [.hearty], goal: .gainMuscle)
        let held = MealScore.coins(eaten: 1400, target: 1400, kinds: [.hearty], goal: .maintain)
        let away = MealScore.coins(eaten: 900, target: 1400, kinds: [.hearty], goal: .maintain)
        let reversed = MealScore.balance(afterRemoving: 20, from: 0)
        let locked = ChallengeCheckoff.allowsHand(category: .other, linkedWorkouts: 0, followsNutrition: true)
        let passed = over == 0
            && underMuscle == 0
            && reached == 20
            && held == 20
            && away == 0
            && reversed == -20
            && !locked
            && ChallengeCheckoff.followsNutrition("nutrition:calories")
            && NutritionCopy.challengeTitle(for: .gainMuscle) == L("Muskelaufbau", "Build muscle")
            && NutritionCopy.challengeTitle(for: .maintain) == L("Kalorien halten", "Hold calories")
        let reading = "0, -20"
        return RuleScenario(
            name: "Ein Ziel entscheidet die Ernährungs-Coins",
            passed: passed,
            detail: passed ? nil : "\(over), \(underMuscle), \(reached), \(reversed)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func calendarOpensOnToday() -> RuleScenario {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14)) ?? .now
        let days = AgendaScroll.days(around: today, calendar: calendar)
        let index = AgendaScroll.todayIndex(in: days, today: today, calendar: calendar)
        let left = ChallengeTimeRules.remaining(slotMinutes: 120, linkedMinutes: [75])
        let parts = ChallengeTimeRules.durationParts(125)
        let group = EventGroupName.title(event: "Zahnarzt", day: "14.11.2026")
        let passed = index == AgendaScroll.pastDays
            && days.count == AgendaScroll.pastDays + 1 + AgendaScroll.futureDays
            && left == 45
            && parts.hours == 2
            && parts.minutes == 5
            && group == "Zahnarzt – 14.11.2026"
            && EventOffer.enabled(stored: nil)
            && !EventOffer.enabled(stored: false)
        let reading = "30, 45"
        return RuleScenario(
            name: "Der Kalender öffnet beim heutigen Tag",
            passed: passed,
            detail: passed ? nil : "\(index ?? -1), \(left), \(group)",
            reading: reading,
            kind: .unit,
            topic: .training
        )
    }

    static func nutrientCardNamesTheMainThree() -> RuleScenario {
        let protein = NutrientGuide.daily(.protein, weightKg: 70, sex: .female, goal: .loseFat, calorieTarget: 1698)
        let fiber = NutrientGuide.daily(.fiber, weightKg: 70, sex: .female, goal: .loseFat, calorieTarget: 1698)
        let passed = NutrientGuide.headlines == [.protein, .carbohydrate, .fat]
            && protein == 112
            && fiber == 30
            && NutrientGuide.daily(.carbohydrate, weightKg: 70, sex: .female, goal: .loseFat, calorieTarget: 2000) == 225
            && NutrientGuide.daily(.fat, weightKg: 70, sex: .female, goal: .loseFat, calorieTarget: 2000) == 67
        let reading = "112, 30"
        return RuleScenario(
            name: "Eiweiß, Kohlenhydrate und Fett stehen groß",
            passed: passed,
            detail: passed ? nil : "\(protein), \(fiber)",
            reading: reading,
            kind: .integration,
            topic: .training
        )
    }

    static func finishedChallengeStaysInItsGroup() -> RuleScenario {
        let open = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let done = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let suggested = ChallengeTimeRules.offeredSuggestions(
            candidates: [
                (id: done, minutes: 20, createdAt: now.addingTimeInterval(-86_400), offered: true, finished: true),
                (id: open, minutes: nil, createdAt: now, offered: true, finished: false)
            ],
            already: []
        )
        let passed = suggested == [open]
            && !ChallengeActivity.staysOnActiveList(recurrence: .none, hasCompletion: true)
            && ChallengeGroupBoard.keepsFinishedMember(archived: false)
            && !ChallengeGroupBoard.keepsFinishedMember(archived: true)
            && !ChallengeGroupBoard.showsInPinned(pinned: false)
            && ChallengeGroupBoard.showsInOwnSection(pinned: false)
            && ChallengeGroupBoard.showsInPinned(pinned: true)
            && !ChallengeGroupBoard.showsInOwnSection(pinned: true)
        let reading = "Gruppe, aus"
        return RuleScenario(
            name: "Eine erledigte Challenge bleibt in der Gruppe",
            passed: passed,
            detail: passed ? nil : suggested.map(\.uuidString).joined(separator: ", "),
            reading: reading,
            kind: .integration,
            topic: .challenge
        )
    }

    static func singleFilterShowsGroupedChallenges() -> RuleScenario {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000051")!
        let late = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let members = EventChallengeLink.members(already: [first], linked: nil, adding: late)
        let passed = EventChallengeLink.showsIndividual(inGroup: true, singleFilter: true)
            && !EventChallengeLink.showsIndividual(inGroup: true, singleFilter: false)
            && EventChallengeLink.showsIndividual(inGroup: false, singleFilter: false)
            && members == [first, late]
            && EventChallengeLink.makesGroup(count: members.count)
        let reading = "einzeln, \(members.count)"
        return RuleScenario(
            name: "Einzeln zeigt die Challenges einer Gruppe",
            passed: passed,
            detail: passed ? nil : "\(members.count)",
            reading: reading,
            kind: .integration,
            topic: .challenge
        )
    }

    static func pinnedChallengesStayAboveTheFilter() -> RuleScenario {
        let ids = (1...6).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-00000000008%d", $0))! }
        let pinned = Array(ids.prefix(ChallengePinStore.limit))
        let below = ChallengePinLayout.below(ids: ids, pinned: pinned)
        let passed = pinned.count == 4
            && below == Array(ids.suffix(2))
            && ChallengePinStore.limit == 4
        let reading = "\(pinned.count), \(below.count)"
        return RuleScenario(
            name: "Angepinnte Challenges stehen über dem Filter",
            passed: passed,
            detail: passed ? nil : "\(below.count)",
            reading: reading,
            kind: .integration,
            topic: .challenge
        )
    }

    static func deletingAGroupCanLeaveTheChallenges() -> RuleScenario {
        let eventGroup = UUID(uuidString: "00000000-0000-0000-0000-000000000093")!
        let chosen = UUID(uuidString: "00000000-0000-0000-0000-000000000094")!
        let kept = GroupRemoval.remaining([chosen, eventGroup], removing: eventGroup)
        let passed = kept == [chosen]
            && GroupRemoval.clearsCalendarLink(generatedFromEvent: true)
            && !GroupRemoval.clearsCalendarLink(generatedFromEvent: false)
        let reading = "einzeln, \(kept.count)"
        return RuleScenario(
            name: "Nur die Gruppe löschen lässt die Challenges einzeln",
            passed: passed,
            detail: passed ? nil : "\(kept.count)",
            reading: reading,
            kind: .integration,
            topic: .challenge
        )
    }

    static func eventGroupStopsWhenTheSlotIsFull() -> RuleScenario {
        let line = ChallengeCardCopy.scheduleLine(recurrence: L("Einmalig", "Once"), minutes: 30)
        let open = GroupJoin.canJoin(linkedToEvent: false, oneTime: true, minutes: 200, remaining: 0)
        let fits = GroupJoin.canJoin(linkedToEvent: true, oneTime: true, minutes: 30, remaining: 30)
        let over = GroupJoin.canJoin(linkedToEvent: true, oneTime: true, minutes: 31, remaining: 30)
        let weekly = GroupJoin.canJoin(linkedToEvent: true, oneTime: false, minutes: nil, remaining: 90)
        let lineOK = line == "Einmalig - 30 Minuten" || line == "Once - 30 minutes"
        let passed = lineOK && open && fits && !over && !weekly
        let reading = open && !over ? "offen, voll" : "zu"
        return RuleScenario(
            name: "Eine Termin-Gruppe nimmt Challenges nur bis der Slot voll ist",
            passed: passed,
            detail: passed ? nil : line,
            reading: reading,
            kind: .integration,
            topic: .challenge
        )
    }
}
