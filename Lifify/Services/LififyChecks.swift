import Foundation

enum LififyCheckKind: String, Equatable {
    case unit
    case integration

    var label: String {
        switch self {
        case .unit: "Unit"
        case .integration: "Integration"
        }
    }
}

enum LififyCheckTopic: String, CaseIterable, Equatable {
    case streak
    case multiplier
    case challenge
    case calendar
    case training
    case abstinence
    case developer
    case finance
    case screen
    case account
    case forecast
    case budget
    case portfolio
    case bankImport
    case backup
    case shop
    case navigation

    var title: String {
        switch self {
        case .streak: L("Streak", "Streak")
        case .multiplier: L("Multiplikator", "Multiplier")
        case .challenge: L("Challenge", "Challenge")
        case .calendar: L("Kalender", "Calendar")
        case .training: L("Training", "Training")
        case .abstinence: L("Abstinenz", "Abstinence")
        case .developer: L("Entwicklermodus", "Developer mode")
        case .finance: L("Finanzen", "Finance")
        case .screen: L("Oberfläche", "Screens")
        case .account: L("Konten", "Accounts")
        case .forecast: L("Prognose", "Forecast")
        case .budget: L("Budget", "Budget")
        case .portfolio: L("Depot", "Portfolio")
        case .bankImport: L("Import", "Import")
        case .backup: L("Sicherung", "Backup")
        case .shop: L("Shop", "Shop")
        case .navigation: L("Navigation", "Navigation")
        }
    }
}

struct LififyCheckResult: Identifiable, Equatable {
    var name: String
    var passed: Bool
    var detail: String?
    /// The measured values, kept even when the check passed.
    var reading: String = ""
    var kind: LififyCheckKind
    var topic: LififyCheckTopic
    var id: String { name }
}

struct CheckTopicGroup: Identifiable, Equatable {
    var topic: LififyCheckTopic
    var rows: [LififyCheckResult]
    var id: String { topic.rawValue }
    var passedCount: Int { rows.filter(\.passed).count }
    var summary: String { "\(passedCount)/\(rows.count)" }
    var allPassed: Bool { passedCount == rows.count }
}

enum CheckResultList {
    /// The test screen opens with every category collapsed.
    static let startsCollapsed = true

    static func groups(from results: [LififyCheckResult]) -> [CheckTopicGroup] {
        LififyCheckTopic.allCases.compactMap { topic in
            let rows = results.filter { $0.topic == topic }
            return rows.isEmpty ? nil : CheckTopicGroup(topic: topic, rows: ordered(rows))
        }
        .sorted { $0.topic.title.localizedStandardCompare($1.topic.title) == .orderedAscending }
    }

    /// Unit checks first, then integration checks, and alphabetical within each kind.
    private static func ordered(_ rows: [LififyCheckResult]) -> [LififyCheckResult] {
        rows.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .unit }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Regression checks for streaks, link captions, and workout links.
/// They only read models in memory and do not write the user's data.
@MainActor
enum LififyChecks {
    static func run() -> [LififyCheckResult] {
        let results = [
            multiplierReplacesLowerStep(),
            defaultMultipliersMatchSettings(),
            defaultMultiplierScalesTheBaseReward(),
            freezePriceUsesWholeFactor(),
            weeklyQuotaWhileOpen(),
            extraDaysStillCount(),
            weeklyQuotaKeepsStreakWithFreeze(),
            weeklyQuotaResetsAfterFreezes(),
            monthlyQuota(),
            dailyStreakCountsEachDay(),
            recurringChallengeStaysActive(),
            completionHistoryGroupsByDay(),
            dueDatesFollowRecurrence(),
            coinsStayAtBaseWithoutStreak(),
            challengeCaptionNamesTheChallenge(),
            calendarCaptionNamesTheEntry(),
            countedCalendarTitles(),
            syncWindowCoversOneYear(),
            seriesKeepsChallengeLink(),
            syncKeepsEventsOutsideTheWindow(),
            nextYearInWindowJoinsTheLinkedWorkout(),
            linkingChallengePullsCalendar(),
            linkingEventPullsChallenge(),
            removingChallengeDropsItsEvents(),
            uncheckingOneEventDropsTheChallenge(),
            manualEventStaysOffTheChallenge(),
            nextOccurrenceJoinsWorkout(),
            workoutClockUsesFiveMinutes(),
            abstinenceClockCountsUp(),
            abstinenceBonusUsesDifficulty(),
            abstinenceMilestonesStayInOrder(),
            abstinenceRunPaysDaysAndStepsOnce(),
            abstinenceExceptionLeavesTheTimer(),
            challengeSlotFitsFourOfFive(),
            finishedChallengesShrinkTheSlot(),
            challengeBelongsToEventAndGroup(),
            emptyNutritionDayKeepsStartingFreezes(),
            calendarLineSitsOnTheGroup(),
            scheduleLineAndOpenGroup(),
            oldChallengesAreSuggested(),
            briefingNamesTheDay(),
            todaysAbstinenceNoticeOnly(),
            openChallengesGetEveningAndClock(),
            streakWarningAndBirthdayFollowTheClock(),
            recentEventsCanBeAssigned(),
            linkingSetsTheChallengeDay(),
            categoriesSplitTheActiveList(),
            briefingClockFollowsTheWeekday(),
            shopTilesShareARow(),
            abstinenceHistoryStaysOneRow(),
            birthdayPaysFiveHundredOnce(),
            birthdayFollowsTheYear(),
            developerDayKeepsClockTime()
        ] + LififyFeatureChecks.run() + LififyCoverageChecks.run() + LififySessionChecks.run()
        return results + [storiesExplainEveryCheck(results)]
    }

    private static func storiesExplainEveryCheck(_ results: [LififyCheckResult]) -> LififyCheckResult {
        let missing = results.filter { !CheckStories.isComplete($0.name) }.map(\.name)
        let passed = missing.isEmpty && CheckStories.isComplete("Jede Prüfung erklärt ihre Schritte")
        return result(
            "Jede Prüfung erklärt ihre Schritte",
            .screen,
            .integration,
            passed,
            missing.joined(separator: ", ")
        )
    }

    private static func multiplierReplacesLowerStep() -> LififyCheckResult {
        let atTwelve = StreakSettings.factor(forStreak: 12, configured: [5: 1.1, 10: 1.2])
        let atSeven = StreakSettings.factor(forStreak: 7, configured: [5: 1.1, 10: 1.2])
        let unsetHigher = StreakSettings.factor(forStreak: 12, configured: [5: 1.1])
        let passed = atTwelve == 1.2 && atSeven == 1.1 && unsetHigher == 1.1
        return result("Multiplikator ersetzt die niedrigere Stufe", .multiplier, .unit, passed, "12× \(atTwelve), 7× \(atSeven), ohne 10er \(unsetHigher)")
    }

    private static func challengeCaptionNamesTheChallenge() -> LififyCheckResult {
        let text = LinkCaption.challenge("Gym")
        let passed = text == "Mit Challenge Gym verknüpft" || text == "Linked to challenge Gym"
        return result("Challenge-Name im Kalender", .calendar, .unit, passed, text)
    }

    private static func calendarCaptionNamesTheEntry() -> LififyCheckResult {
        let when = AppDate.numeric(day(2026, 10, 25))
        let text = LinkCaption.calendar(titles: ["Gym"], count: 1, singleDate: day(2026, 10, 25))
        let passed = text == "Mit Kalender Gym · \(when) verknüpft" || text == "Linked to calendar Gym · \(when)"
        return result("Kalendereintrag in der Challenge", .calendar, .unit, passed, text ?? "leer")
    }

    private static func developerDayKeepsClockTime() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)) ?? .distantPast
        let time = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 16, minute: 5, second: 9)) ?? .distantPast
        let combined = AppClock.combining(day: day, time: time, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: combined)
        let stamp = AppClock.stamp(year: 2026, month: 11, day: 2)
        let berlinKept = keptDay(stamp, zone: "Europe/Berlin")
        let yorkKept = keptDay(stamp, zone: "America/New_York")
        var zone = Calendar(identifier: .gregorian)
        zone.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let moment = zone.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 8, minute: 30)) ?? .distantPast
        let wall = NotificationTiming.components(for: moment, followsDeviceTimeZone: true, calendar: zone)
        let fixed = NotificationTiming.components(for: moment, followsDeviceTimeZone: false, calendar: zone)
        let passed = parts.year == 2026 && parts.month == 11 && parts.day == 2
            && parts.hour == 16 && parts.minute == 5 && parts.second == 9
            && berlinKept && yorkKept
            && CalendarService.timeZone.identifier == TimeZone.autoupdatingCurrent.identifier
            && wall.timeZone == nil && wall.hour == 8 && wall.minute == 30
            && fixed.timeZone?.identifier == "Europe/Berlin" && fixed.hour == 8
        return result(
            "Entwicklertag behält die Uhrzeit",
            .developer,
            .unit,
            passed,
            "\(parts.day ?? 0).\(parts.month ?? 0). \(parts.hour ?? 0):\(parts.minute ?? 0), Wand \(wall.hour ?? -1), fest \(fixed.timeZone?.identifier ?? "-")"
        )
    }

    private static func keptDay(_ stamp: String, zone: String) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        let time = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 16, minute: 5, second: 9)) ?? .distantPast
        guard let combined = AppClock.combining(stamp: stamp, time: time, calendar: calendar) else { return false }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: combined)
        return parts.year == 2026 && parts.month == 11 && parts.day == 2
            && parts.hour == 16 && parts.minute == 5 && parts.second == 9
    }

    private static func linkingChallengePullsCalendar() -> LififyCheckResult {
        let gym = UUID()
        let monday = UUID()
        let wednesday = UUID()
        let manual = UUID()
        let calendar = [
            WorkoutLinkRules.CalendarLink(eventID: monday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: wednesday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: manual, challengeID: nil)
        ]
        let next = WorkoutLinkRules.applyChallenges(
            [gym],
            previous: .init(challenges: [], events: [manual]),
            calendar: calendar
        )
        let passed = next.challenges == [gym] && next.events == [monday, wednesday, manual]
        return result("Challenge zieht ihre Kalendereinträge nach", .training, .unit, passed, "Termine \(next.events.count)")
    }

    private static func linkingEventPullsChallenge() -> LififyCheckResult {
        let gym = UUID()
        let monday = UUID()
        let wednesday = UUID()
        let calendar = [
            WorkoutLinkRules.CalendarLink(eventID: monday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: wednesday, challengeID: gym)
        ]
        let next = WorkoutLinkRules.applyEvents(
            [monday],
            previous: .init(challenges: [], events: []),
            calendar: calendar
        )
        let passed = next.challenges == [gym] && next.events == [monday, wednesday]
        return result("Kalendereintrag zieht Challenge und Geschwister nach", .training, .unit, passed, "Challenges \(next.challenges.count), Termine \(next.events.count)")
    }

    private static func removingChallengeDropsItsEvents() -> LififyCheckResult {
        let gym = UUID()
        let other = UUID()
        let monday = UUID()
        let wednesday = UUID()
        let manual = UUID()
        let calendar = [
            WorkoutLinkRules.CalendarLink(eventID: monday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: wednesday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: manual, challengeID: nil)
        ]
        let previous = WorkoutLinkRules.Snapshot(challenges: [gym, other], events: [monday, wednesday, manual])
        let kept = WorkoutLinkRules.applyChallenges([other], previous: previous, calendar: calendar)
        let cleared = WorkoutLinkRules.applyChallenges([], previous: previous, calendar: calendar)
        let passed = kept.challenges == [other] && kept.events == [manual]
            && cleared.challenges.isEmpty && cleared.events == [manual]
        return result(
            "Challenge lösen entfernt nur ihre Termine",
            .training,
            .unit,
            passed,
            "Bleibt \(kept.challenges.count)/\(kept.events.count), leer \(cleared.challenges.count)/\(cleared.events.count)"
        )
    }

    private static func uncheckingOneEventDropsTheChallenge() -> LififyCheckResult {
        let gym = UUID()
        let monday = UUID()
        let wednesday = UUID()
        let manual = UUID()
        let calendar = [
            WorkoutLinkRules.CalendarLink(eventID: monday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: wednesday, challengeID: gym),
            WorkoutLinkRules.CalendarLink(eventID: manual, challengeID: nil)
        ]
        let previous = WorkoutLinkRules.Snapshot(challenges: [gym], events: [monday, wednesday, manual])
        let next = WorkoutLinkRules.applyEvents([wednesday, manual], previous: previous, calendar: calendar)
        let passed = next.challenges.isEmpty && next.events == [manual]
        return result("Einen Termin abwählen löst die Challenge", .training, .unit, passed, "Challenges \(next.challenges.count), Termine \(next.events.count)")
    }

    private static func manualEventStaysOffTheChallenge() -> LififyCheckResult {
        let gym = UUID()
        let other = UUID()
        let monday = UUID()
        let manual = UUID()
        let foreign = UUID()
        let closed = WorkoutLinkRules.close(
            challenges: [gym],
            events: [],
            calendar: [
                WorkoutLinkRules.CalendarLink(eventID: monday, challengeID: gym),
                WorkoutLinkRules.CalendarLink(eventID: manual, challengeID: nil),
                WorkoutLinkRules.CalendarLink(eventID: foreign, challengeID: other)
            ]
        )
        let passed = closed.challenges == [gym] && closed.events == [monday]
        return result("Manuelle und fremde Termine bleiben draußen", .training, .integration, passed, "Termine \(closed.events.count)")
    }

    private static func weeklyQuotaWhileOpen() -> LififyCheckResult {
        let status = weeklyStatus(
            eventsOn: [day(2026, 10, 5), day(2026, 10, 7), day(2026, 10, 9)],
            completionsOn: [day(2026, 10, 5), day(2026, 10, 8)],
            endingOn: day(2026, 10, 8),
            purchasedFreezes: 0
        )
        let passed = status.count == 2 && status.required == 3 && status.done == 2
        return result("Offene Woche zählt beliebige Tage", .streak, .integration, passed, "Serie \(status.count), \(status.done)/\(status.required)")
    }

    private static func extraDaysStillCount() -> LififyCheckResult {
        let challenge = ChallengeItem(title: "Gym", category: .sport, recurrence: .weekly, startDate: day(2026, 10, 5), weeklyDays: [2, 4, 6])
        let completions = [day(2026, 10, 6), day(2026, 10, 7), day(2026, 10, 8), day(2026, 10, 11)].map {
            ChallengeCompletion(challengeID: challenge.id, date: $0, earnedCoins: 0)
        }
        let status = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 11),
            completions: completions,
            events: [],
            streakState: streakState(purchased: 0),
            usesStoredState: false
        )
        let passed = status.required == 3 && status.done == 4 && status.count == 4
        return result("Mehr Tage als die Woche verlangt zählen mit", .streak, .integration, passed, "Serie \(status.count), \(status.done)/\(status.required)")
    }

    private static func weeklyQuotaKeepsStreakWithFreeze() -> LififyCheckResult {
        let status = weeklyStatus(
            eventsOn: [day(2026, 10, 5), day(2026, 10, 7), day(2026, 10, 9)],
            completionsOn: [day(2026, 10, 5), day(2026, 10, 8)],
            endingOn: day(2026, 10, 12),
            purchasedFreezes: 0
        )
        let passed = status.count == 2 && status.freezeKeys.count == 1
        return result("Freeze hält die angefangene Serie", .streak, .integration, passed, "Serie \(status.count), Freezes verbraucht \(status.freezeKeys.count)")
    }

    private static func weeklyQuotaResetsAfterFreezes() -> LififyCheckResult {
        let status = weeklyStatus(
            eventsOn: [
                day(2026, 10, 5), day(2026, 10, 7), day(2026, 10, 9),
                day(2026, 10, 12), day(2026, 10, 14), day(2026, 10, 16),
                day(2026, 10, 19), day(2026, 10, 21), day(2026, 10, 23)
            ],
            completionsOn: [day(2026, 10, 5), day(2026, 10, 8)],
            endingOn: day(2026, 10, 26),
            purchasedFreezes: 0
        )
        let passed = status.count == 0 && status.freezeKeys.count == 2
        return result("Dritte verpasste Woche setzt die Serie auf 0", .streak, .integration, passed, "Serie \(status.count), Freezes verbraucht \(status.freezeKeys.count)")
    }

    private static func monthlyQuota() -> LififyCheckResult {
        let challenge = ChallengeItem(
            title: "Monatsabschluss",
            recurrence: .monthly,
            startDate: day(2026, 10, 1)
        )
        let completions = [ChallengeCompletion(challengeID: challenge.id, date: day(2026, 10, 10), earnedCoins: 0)]
        let state = streakState(purchased: 0)
        let open = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 20),
            completions: completions,
            events: [],
            streakState: state,
            usesStoredState: false
        )
        let afterNovember = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 12, 15),
            completions: completions,
            events: [],
            streakState: state,
            usesStoredState: false
        )
        let passed = open.count == 1 && open.required == 1 && open.done == 1
            && afterNovember.count == 1 && afterNovember.freezeKeys.count == 1 && afterNovember.required == 1
        return result(
            "Einmal im Monat, Freeze hält den Folgemonat",
            .streak,
            .integration,
            passed,
            "Offen \(open.count), danach Serie \(afterNovember.count), Freezes \(afterNovember.freezeKeys.count)"
        )
    }

    private static func dailyStreakCountsEachDay() -> LififyCheckResult {
        let challenge = ChallengeItem(title: "Täglich", recurrence: .daily, startDate: day(2026, 10, 5))
        let completions = [day(2026, 10, 5), day(2026, 10, 6), day(2026, 10, 7)].map {
            ChallengeCompletion(challengeID: challenge.id, date: $0, earnedCoins: 0)
        }
        let status = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 7),
            completions: completions,
            events: [],
            streakState: streakState(purchased: 0),
            usesStoredState: false
        )
        let passed = status.count == 3 && status.required == 1 && status.done == 1
        return result("Tägliche Serie zählt jeden Tag", .streak, .integration, passed, "Serie \(status.count), heute \(status.done)/\(status.required)")
    }

    private static func defaultMultipliersMatchSettings() -> LififyCheckResult {
        let expected: [Int: Double] = [
            5: 1.1, 10: 1.2, 15: 1.3, 20: 1.4, 25: 1.5,
            50: 1.75, 100: 2, 200: 2.25, 250: 2.5, 500: 2.75, 1000: 3
        ]
        let merged = StreakSettings.merging([5: 9])
        let passed = StreakSettings.defaultMultipliers == expected
            && StreakSettings.merging([:]) == expected
            && merged[5] == 9
            && merged[10] == 1.2
        return result("Standardwerte bleiben, bis eine Stufe geändert wird", .multiplier, .unit, passed, "5× \(merged[5] ?? 0)")
    }

    private static func defaultMultiplierScalesTheBaseReward() -> LififyCheckResult {
        let challenge = ChallengeItem(title: "Gym", recurrence: .daily, startDate: day(2026, 10, 1), rewardCoins: 10)
        let completions = (1...12).map {
            ChallengeCompletion(challengeID: challenge.id, date: day(2026, 10, $0), earnedCoins: 0)
        }
        let status = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 12),
            completions: completions,
            events: [],
            streakState: StreakSettings.State(enabled: true, enabledAt: day(2026, 10, 1), purchased: 0, usedPeriodKeys: []),
            usesStoredState: false
        )
        let factor = StreakSettings.factor(forStreak: status.count, configured: StreakSettings.defaultMultipliers)
        let coins = Int((Double(challenge.rewardCoins) * factor).rounded())
        let atFour = StreakSettings.factor(forStreak: 4, configured: StreakSettings.defaultMultipliers)
        let atThousand = StreakSettings.factor(forStreak: 1000, configured: StreakSettings.defaultMultipliers)
        let passed = status.count == 12 && factor == 1.2 && coins == 12 && atFour == 1 && atThousand == 3
        return result("Standard-Multiplikator skaliert die Basis-Belohnung", .multiplier, .integration, passed, "Serie \(status.count), Faktor \(factor), Coins \(coins)")
    }

    private static func freezePriceUsesWholeFactor() -> LififyCheckResult {
        let ten = StreakSettings.price(rewardCoins: 12, factor: 10)
        let twenty = StreakSettings.price(rewardCoins: 12, factor: 20)
        let minimum = StreakSettings.price(rewardCoins: 12, factor: 0)
        let wholeTen = StreakSettings.wholeFactor(from: "10")
        let wholeTwenty = StreakSettings.wholeFactor(from: "20")
        let fraction = StreakSettings.wholeFactor(from: "10,5")
        let dotted = StreakSettings.wholeFactor(from: "1.5")
        let zero = StreakSettings.wholeFactor(from: "0")
        let empty = StreakSettings.wholeFactor(from: "")
        let passed = ten == 120 && twenty == 240 && minimum == 12
            && wholeTen == 10 && wholeTwenty == 20
            && fraction == nil && dotted == nil && zero == nil && empty == nil
        return result("Freeze-Preis ist ein ganzzahliger Faktor", .streak, .unit, passed, "10× \(ten), 20× \(twenty), Faktor \(wholeTen ?? 0)")
    }

    private static func recurringChallengeStaysActive() -> LififyCheckResult {
        let weeklyStays = ChallengeActivity.staysOnActiveList(recurrence: .weekly, hasCompletion: true)
        let onceLeaves = !ChallengeActivity.staysOnActiveList(recurrence: .none, hasCompletion: true)
        let onceOpen = ChallengeActivity.staysOnActiveList(recurrence: .none, hasCompletion: false)
        let gray = ChallengeActivity.dimsActiveRow(recurrence: .daily, completedToday: true)
        let notGrayLater = !ChallengeActivity.dimsActiveRow(recurrence: .daily, completedToday: false)
        let plain = !ChallengeActivity.dimsActiveRow(recurrence: .none, completedToday: true)
        let passed = weeklyStays && onceLeaves && onceOpen && gray && notGrayLater && plain
        return result("Wiederkehrend bleibt aktiv und wird heute grau", .challenge, .unit, passed, "aktiv \(weeklyStays), einmalig weg \(onceLeaves)")
    }

    private static func completionHistoryGroupsByDay() -> LififyCheckResult {
        let gym = UUID()
        let reading = UUID()
        let days = ChallengeHistory.grouped(completions: [
            ChallengeHistoryCompletion(challengeID: gym, title: "Gym", date: day(2026, 10, 25)),
            ChallengeHistoryCompletion(challengeID: gym, title: "Gym", date: day(2026, 10, 25)),
            ChallengeHistoryCompletion(challengeID: reading, title: "Lesen", date: day(2026, 10, 25)),
            ChallengeHistoryCompletion(challengeID: gym, title: "Gym", date: day(2026, 10, 24))
        ])
        let first = days.first
        let passed = days.count == 2
            && first?.entries.map(\.title) == ["Gym", "Lesen"]
            && first?.entries.map(\.challengeID) == [gym, reading]
            && days.last?.entries.map(\.title) == ["Gym"]
            && days.last?.entries.map(\.challengeID) == [gym]
        return result("Verlauf gruppiert erledigte Challenges nach Tag", .challenge, .integration, passed, "Tage \(days.count), heute \(first?.entries.count ?? 0)")
    }

    private static func dueDatesFollowRecurrence() -> LififyCheckResult {
        let weekly = ChallengeItem(title: "Gym", recurrence: .weekly, startDate: day(2026, 10, 5), weeklyDays: [2, 4, 6])
        let daily = ChallengeItem(title: "Lesen", recurrence: .daily, startDate: day(2026, 10, 5))
        let monthly = ChallengeItem(title: "Monat", recurrence: .monthly, startDate: day(2026, 10, 25))
        let once = ChallengeItem(title: "Einmal", recurrence: .none, startDate: day(2026, 10, 25))
        let yearly = ChallengeItem(title: "Jahr", recurrence: .yearly, startDate: day(2026, 10, 25))
        let passed = ChallengeService.isDue(weekly, on: day(2026, 10, 5))
            && !ChallengeService.isDue(weekly, on: day(2026, 10, 6))
            && ChallengeService.isDue(daily, on: day(2026, 10, 6))
            && !ChallengeService.isDue(daily, on: day(2026, 10, 4))
            && ChallengeService.isDue(monthly, on: day(2026, 11, 25))
            && !ChallengeService.isDue(monthly, on: day(2026, 11, 24))
            && ChallengeService.isDue(once, on: day(2026, 10, 25))
            && !ChallengeService.isDue(once, on: day(2026, 10, 26))
            && ChallengeService.isDue(yearly, on: day(2027, 10, 25))
            && !ChallengeService.isDue(yearly, on: day(2027, 10, 26))
        return result("Fällig folgt täglich, wöchentlich, monatlich, jährlich und einmalig", .challenge, .integration, passed, "Woche \(ChallengeService.isDue(weekly, on: day(2026, 10, 5)))")
    }

    private static func coinsStayAtBaseWithoutStreak() -> LififyCheckResult {
        let challenge = ChallengeItem(title: "Gym", rewardCoins: 15)
        let coins = ChallengeService.projectedCoins(
            challenge: challenge,
            on: day(2026, 10, 25),
            completions: [],
            events: []
        )
        let passed = coins == 15
        return result("Ohne Streak bleibt die Basis-Belohnung", .challenge, .integration, passed, "Coins \(coins)")
    }

    private static func countedCalendarTitles() -> LififyCheckResult {
        let text = LinkCaption.countedTitles(["GYM", "GYM", "GYM", "Officeday"])
        let passed = text == "GYM · 3, Officeday"
        return result("Gleiche Kalendertitel werden zusammengezählt", .calendar, .unit, passed, text)
    }

    private static func syncWindowCoversOneYear() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)) ?? .distantPast
        let soon = calendar.date(byAdding: .day, value: 200, to: now) ?? .distantFuture
        let later = calendar.date(byAdding: .day, value: 400, to: now) ?? .distantPast
        let recent = calendar.date(byAdding: .day, value: -10, to: now) ?? .distantPast
        let old = calendar.date(byAdding: .day, value: -40, to: now) ?? .distantFuture
        let passed = CalendarSyncWindow.contains(soon, around: now, calendar: calendar)
            && !CalendarSyncWindow.contains(later, around: now, calendar: calendar)
            && CalendarSyncWindow.contains(recent, around: now, calendar: calendar)
            && !CalendarSyncWindow.contains(old, around: now, calendar: calendar)
        return result("Sync umfasst ein Jahr voraus und 30 Tage zurück", .calendar, .unit, passed, "Fenster \(CalendarSyncWindow.pastDays)/\(CalendarSyncWindow.futureDays)")
    }

    private static func seriesKeepsChallengeLink() -> LififyCheckResult {
        let gym = UUID()
        let group = UUID()
        let reward = UUID()
        let links = CalendarSeriesLink.links(externalIdentifier: "series-gym", events: [
            CalendarSeriesLink.Event(externalIdentifier: "series-gym", challengeID: nil, groupID: group, rewardID: nil),
            CalendarSeriesLink.Event(externalIdentifier: "series-gym", challengeID: gym, groupID: nil, rewardID: reward),
            CalendarSeriesLink.Event(externalIdentifier: "other", challengeID: UUID(), groupID: UUID(), rewardID: UUID())
        ])
        let passed = links.challengeID == gym && links.groupID == group && links.rewardID == reward
        return result("Neue Serientermine behalten die Challenge", .calendar, .unit, passed, "Challenge \(links.challengeID == gym)")
    }

    private static func syncKeepsEventsOutsideTheWindow() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)) ?? .distantPast
        let recent = calendar.date(byAdding: .day, value: -10, to: now) ?? .distantPast
        let old = calendar.date(byAdding: .day, value: -40, to: now) ?? .distantFuture
        let soon = calendar.date(byAdding: .day, value: 200, to: now) ?? .distantFuture
        let later = calendar.date(byAdding: .day, value: 400, to: now) ?? .distantPast
        let passed = CalendarSyncWindow.removesImportedEvent(start: recent, externalIdentifier: "gym", matched: false, around: now, calendar: calendar)
            && CalendarSyncWindow.removesImportedEvent(start: soon, externalIdentifier: "gym", matched: false, around: now, calendar: calendar)
            && !CalendarSyncWindow.removesImportedEvent(start: old, externalIdentifier: "gym", matched: false, around: now, calendar: calendar)
            && !CalendarSyncWindow.removesImportedEvent(start: later, externalIdentifier: "gym", matched: false, around: now, calendar: calendar)
            && !CalendarSyncWindow.removesImportedEvent(start: recent, externalIdentifier: "gym", matched: true, around: now, calendar: calendar)
            && !CalendarSyncWindow.removesImportedEvent(start: recent, externalIdentifier: "reminder:1", matched: false, around: now, calendar: calendar)
            && !CalendarSyncWindow.removesImportedEvent(start: recent, externalIdentifier: nil, matched: false, around: now, calendar: calendar)
        return result("Sync löscht nur verschwundene Termine im Jahresfenster", .calendar, .integration, passed, "alt bleibt")
    }

    private static func nextYearInWindowJoinsTheLinkedWorkout() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)) ?? .distantPast
        let soon = calendar.date(byAdding: .day, value: 200, to: now) ?? .distantFuture
        let later = calendar.date(byAdding: .day, value: 400, to: now) ?? .distantPast
        let gym = UUID()
        let currentYear = UUID()
        let nextYear = UUID()
        let links = CalendarSeriesLink.links(externalIdentifier: "gym", events: [
            CalendarSeriesLink.Event(externalIdentifier: "gym", challengeID: gym, groupID: nil, rewardID: nil)
        ])
        let imported = CalendarSyncWindow.contains(soon, around: now, calendar: calendar)
            && !CalendarSyncWindow.contains(later, around: now, calendar: calendar)
        let closed = WorkoutLinkRules.close(
            challenges: [gym],
            events: [currentYear],
            calendar: [
                WorkoutLinkRules.CalendarLink(eventID: currentYear, challengeID: links.challengeID),
                WorkoutLinkRules.CalendarLink(eventID: nextYear, challengeID: links.challengeID)
            ]
        )
        let passed = imported && links.challengeID == gym && closed.events == [currentYear, nextYear]
        return result("Termin im Jahresfenster hängt an Challenge und Training", .calendar, .integration, passed, "Termine \(closed.events.count)")
    }

    private static func nextOccurrenceJoinsWorkout() -> LififyCheckResult {
        let gym = UUID()
        let currentYear = UUID()
        let nextYear = UUID()
        let closed = WorkoutLinkRules.close(
            challenges: [gym],
            events: [currentYear],
            calendar: [
                WorkoutLinkRules.CalendarLink(eventID: currentYear, challengeID: gym),
                WorkoutLinkRules.CalendarLink(eventID: nextYear, challengeID: gym)
            ]
        )
        let passed = closed.challenges == [gym] && closed.events == [currentYear, nextYear]
        return result("Termin im nächsten Jahr hängt am Training", .training, .integration, passed, "Termine \(closed.events.count)")
    }

    private static func workoutClockUsesFiveMinutes() -> LififyCheckResult {
        let raw = Date(timeIntervalSinceReferenceDate: 1_000)
        let rounded = WorkoutCalendarSync.clock(raw)
        let passed = rounded.timeIntervalSinceReferenceDate == 900
            && WorkoutCalendarSync.duration(seconds: 0) == 300
            && WorkoutCalendarSync.duration(seconds: 450) == 600
        return result("Training rastet auf fünf Minuten ein", .training, .unit, passed, "Uhr \(rounded.timeIntervalSinceReferenceDate)")
    }

    private static func weeklyStatus(
        eventsOn dates: [Date],
        completionsOn completionDates: [Date],
        endingOn: Date,
        purchasedFreezes: Int
    ) -> ChallengeService.StreakStatus {
        let challenge = ChallengeItem(title: "Gym", category: .sport, recurrence: .weekly, startDate: day(2026, 10, 5))
        let events = dates.map {
            ChallengeCalendarEvent(title: "Gym", startDate: $0, endDate: $0.addingTimeInterval(3600), linkedChallengeID: challenge.id)
        }
        let completions = completionDates.map {
            ChallengeCompletion(challengeID: challenge.id, date: $0, earnedCoins: 0)
        }
        return ChallengeService.status(
            for: challenge,
            endingOn: endingOn,
            completions: completions,
            events: events,
            streakState: streakState(purchased: purchasedFreezes),
            usesStoredState: false
        )
    }

    private static func streakState(purchased: Int) -> StreakSettings.State {
        StreakSettings.State(enabled: true, enabledAt: day(2026, 10, 1), purchased: purchased, usedPeriodKeys: [])
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func abstinenceClockCountsUp() -> LififyCheckResult {
        let zero = AbstinenceRules.clock(-5)
        let minute = AbstinenceRules.clock(3_661)
        let day = AbstinenceRules.clock(86_400 + 3_661)
        let passed = zero == AbstinenceClock(days: 0, hours: 0, minutes: 0, seconds: 0)
            && minute == AbstinenceClock(days: 0, hours: 1, minutes: 1, seconds: 1)
            && day == AbstinenceClock(days: 1, hours: 1, minutes: 1, seconds: 1)
        return result("Timer zählt Tage, Stunden, Minuten und Sekunden", .abstinence, .unit, passed, "\(minute.hours):\(minute.minutes):\(minute.seconds)")
    }

    private static func abstinenceBonusUsesDifficulty() -> LififyCheckResult {
        let easy = AbstinenceRules.defaultMultipliers[.easy] ?? [:]
        let medium = AbstinenceRules.defaultMultipliers[.medium] ?? [:]
        let hard = AbstinenceRules.defaultMultipliers[.hard] ?? [:]
        let ordered = AbstinenceMilestone.allCases.allSatisfy { milestone in
            let key = milestone.rawValue
            return (easy[key] ?? 0) < (medium[key] ?? 0) && (medium[key] ?? 0) < (hard[key] ?? 0)
        }
        let merged = AbstinenceRules.merging(["1h": 9], defaults: medium)
        let half = AbstinenceRules.bonusCoins(base: 10, multiplier: 0.5)
        let fraction = AbstinenceRules.bonusCoins(base: 10, multiplier: 1.5)
        let empty = AbstinenceRules.bonusCoins(base: 0, multiplier: 5)
        let passed = ordered && merged["1h"] == 9 && merged["2h"] == medium["2h"]
            && half == 5 && fraction == 15 && empty == 0
        return result("Schwer zahlt mehr als leicht, ein Faktor bleibt editierbar", .abstinence, .unit, passed, "halb \(half), anderthalb \(fraction)")
    }

    private static func abstinenceMilestonesStayInOrder() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)) ?? .distantPast
        let almostHour = start.addingTimeInterval(3_599)
        let hour = start.addingTimeInterval(3_600)
        let almost72 = start.addingTimeInterval(72 * 3_600 - 1)
        let at72 = start.addingTimeInterval(72 * 3_600)
        let week = AbstinenceMilestone.day7.due(from: start, calendar: calendar)
        let year = AbstinenceMilestone.year1.due(from: start, calendar: calendar)
        let beforeHour = AbstinenceRules.reached(start: start, now: almostHour, calendar: calendar)
        let atHour = AbstinenceRules.reached(start: start, now: hour, calendar: calendar)
        let before72 = AbstinenceRules.reached(start: start, now: almost72, calendar: calendar)
        let reached72 = AbstinenceRules.reached(start: start, now: at72, calendar: calendar)
        let atWeek = AbstinenceRules.reached(start: start, now: week, calendar: calendar)
        let beforeYear = AbstinenceRules.reached(start: start, now: year.addingTimeInterval(-1), calendar: calendar)
        let atYear = AbstinenceRules.reached(start: start, now: year, calendar: calendar)
        let passed = beforeHour.isEmpty
            && atHour == [.hour1]
            && !before72.contains(.hour72) && before72.contains(.hour24)
            && reached72.contains(.hour72) && !reached72.contains(.day7)
            && atWeek.contains(.day7) && !atWeek.contains(.day14)
            && !beforeYear.contains(.year1) && atYear.contains(.year1)
            && AbstinenceMilestone(rawValue: "78h") == nil
        return result("Boni sitzen auf 1, 2, 4, 8, 24 und 72 Stunden, dann 7, 14, 30 Tage und 1 Jahr", .abstinence, .unit, passed, "72h \(reached72.contains(.hour72))")
    }

    private static func abstinenceRunPaysDaysAndStepsOnce() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12)) ?? .distantPast
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12)) ?? .distantFuture
        let first = AbstinenceRules.plan(start: start, now: now, completedDays: [], awarded: [], calendar: calendar)
        let days = Set(AbstinenceRules.dayStarts(from: start, through: now, calendar: calendar))
        let again = AbstinenceRules.plan(start: start, now: now, completedDays: days, awarded: Set(first.milestones.map(\.rawValue)), calendar: calendar)
        let relapseStart = now.addingTimeInterval(-2 * 3_600)
        let relapsed = AbstinenceRules.plan(start: relapseStart, now: now, completedDays: days, awarded: [], calendar: calendar)
        let future = AbstinenceRules.plan(start: now.addingTimeInterval(3_600), now: now, completedDays: [], awarded: [], calendar: calendar)
        let base = 10
        let dayBonus = AbstinenceRules.bonusCoins(base: base, multiplier: AbstinenceRules.defaultMultipliers[.medium]?["24h"] ?? 0)
        let passed = first.days.count == 11
            && first.milestones.contains(.day7)
            && !first.milestones.contains(.day14)
            && first.milestones.contains(.hour72)
            && again.days.isEmpty && again.milestones.isEmpty
            && relapsed.milestones == [.hour1, .hour2]
            && future.days.isEmpty && future.milestones.isEmpty
            && dayBonus == 60
        return result("Ein Lauf zahlt jeden Tag und jede Stufe einmal, ein Rückfall startet die Boni neu", .abstinence, .integration, passed, "Tage \(first.days.count), Stufen \(first.milestones.count), neu \(relapsed.milestones.count)")
    }

    private static func abstinenceExceptionLeavesTheTimer() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 8)) ?? .distantPast
        let now = start.addingTimeInterval(26 * 3_600)
        let before = AbstinenceRules.plan(start: start, now: now, completedDays: [], awarded: [], calendar: calendar)
        let after = AbstinenceRules.plan(start: start, now: now, completedDays: [], awarded: [], calendar: calendar)
        let passed = before == after && before.milestones.contains(.hour24) && !before.milestones.contains(.day7)
        return result("Eine Ausnahme ändert den Timer nicht", .abstinence, .unit, passed, "Stufen \(before.milestones.count)")
    }

    private static func challengeSlotFitsFourOfFive() -> LififyCheckResult {
        let count = ChallengeTimeRules.fitCount(minutes: [30, 30, 30, 30, 30], slotMinutes: 120)
        let caption = LinkCaption.challenges(["Lesen", "Schreiben"])
        let passed = count == 4
            && !ChallengeTimeRules.allowsTime(.sport)
            && !ChallengeTimeRules.allowsTime(.abstinence)
            && ChallengeTimeRules.allowsTime(.habit)
            && ChallengeTimeRules.matches(.withTime, minutes: 30)
            && !ChallengeTimeRules.matches(.withTime, minutes: nil)
            && ChallengeTimeRules.matches(.withoutTime, minutes: nil)
            && (caption == "Mit Challenges Lesen, Schreiben verknüpft" || caption == "Linked to challenges Lesen, Schreiben")
        return result("In zwei Stunden passen vier Challenges à 30 Minuten", .challenge, .unit, passed, "passen \(count), \(caption ?? "leer")")
    }

    private static func finishedChallengesShrinkTheSlot() -> LififyCheckResult {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000062")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18)) ?? .now
        let earlier = end.addingTimeInterval(-50 * 60)
        let window = EventRewrite.window(checkedOffAt: [earlier, end], durations: [20, 40])
        let start = window?.start ?? .distantPast
        let passed = !EventRewrite.ready(memberIDs: [first, second], completedIDs: [first])
            && EventRewrite.ready(memberIDs: [first, second], completedIDs: [first, second])
            && window?.end == end
            && start == end.addingTimeInterval(-60 * 60)
            && EventRewrite.canShare(adding: .none, others: [.none])
            && !EventRewrite.canShare(adding: .weekly, others: [.none])
            && EventRewrite.canShare(adding: .daily, others: [])
        let reading = String(format: "%d:%02d, 2", calendar.component(.hour, from: start), calendar.component(.minute, from: start))
        return result("Der Termin rückt, wenn alle Challenges abgehakt sind", .challenge, .integration, passed, reading)
    }

    private static func challengeBelongsToEventAndGroup() -> LififyCheckResult {
        let chosen = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let eventGroup = UUID(uuidString: "00000000-0000-0000-0000-000000000072")!
        let both = ChallengeGroups.membership(chosen: chosen, eventGroup: eventGroup)
        let stored = ChallengeGroups.ids(primary: chosen, stored: ChallengeGroups.stored(both))
        let passed = both == [chosen, eventGroup]
            && stored == both
            && ChallengeGroups.contains(both, eventGroup)
            && ChallengeGroups.contains(both, chosen)
            && ChallengeGroups.membership(chosen: nil, eventGroup: eventGroup) == [eventGroup]
        let reading = "beide, \(both.count)"
        return result("Eine Challenge bleibt in Termin und Gruppe", .challenge, .unit, passed, reading)
    }

    private static func emptyNutritionDayKeepsStartingFreezes() -> LififyCheckResult {
        let challenge = ChallengeItem(
            title: "Kaloriendefizit",
            recurrence: .daily,
            startDate: day(2026, 10, 5),
            externalIdentifier: NutritionLedger.challengeMark
        )
        let quiet = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 8),
            completions: [],
            events: [],
            streakState: streakState(purchased: 0),
            usesStoredState: false,
            confirmedMeals: { _ in 0 }
        )
        let attempted = ChallengeService.status(
            for: challenge,
            endingOn: day(2026, 10, 8),
            completions: [],
            events: [],
            streakState: streakState(purchased: 0),
            usesStoredState: false,
            confirmedMeals: { _ in 1 }
        )
        let leftQuiet = StreakFreeze.startingCount - quiet.freezeKeys.count
        let leftAttempted = StreakFreeze.startingCount - attempted.freezeKeys.count
        let passed = !StreakFreeze.countsDay(followsNutrition: true, confirmedMeals: 0)
            && StreakFreeze.countsDay(followsNutrition: true, confirmedMeals: 1)
            && StreakFreeze.countsDay(followsNutrition: false, confirmedMeals: 0)
            && quiet.freezeKeys.isEmpty
            && leftQuiet == 2
            && attempted.freezeKeys.count == 2
            && leftAttempted == 0
        let reading = "ohne \(leftQuiet), mit \(leftAttempted)"
        return result("Ein Tag ohne Mahlzeiten lässt die zwei Freezes", .streak, .unit, passed, reading)
    }

    private static func calendarLineSitsOnTheGroup() -> LififyCheckResult {
        let eventGroup = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
        let chosen = UUID(uuidString: "00000000-0000-0000-0000-000000000092")!
        let onGroup = GroupCalendarLine.belongsOnGroup(eventGroupID: eventGroup, membership: [chosen, eventGroup])
        let ownLink = !GroupCalendarLine.belongsOnGroup(eventGroupID: nil, membership: [eventGroup])
        let other = !GroupCalendarLine.belongsOnGroup(eventGroupID: chosen, membership: [eventGroup])
        let passed = onGroup && ownLink && other
        return result("Die Kalenderzeile steht in der Stilfarbe an der Gruppe", .challenge, .unit, passed, "auf der Gruppe")
    }

    private static func scheduleLineAndOpenGroup() -> LififyCheckResult {
        let line = ChallengeCardCopy.scheduleLine(recurrence: L("Einmalig", "Once"), minutes: 20)
        let weekly = ChallengeCardCopy.scheduleLine(recurrence: L("Wöchentlich", "Weekly"), minutes: 30)
        let bare = ChallengeCardCopy.scheduleLine(recurrence: L("Täglich", "Daily"), minutes: nil)
        let zero = ChallengeCardCopy.scheduleLine(recurrence: L("Einmalig", "Once"), minutes: 0)
        let open = GroupJoin.canJoin(linkedToEvent: false, oneTime: false, minutes: 90, remaining: 0)
        let fits = GroupJoin.canJoin(linkedToEvent: true, oneTime: true, minutes: 20, remaining: 30)
        let full = GroupJoin.canJoin(linkedToEvent: true, oneTime: true, minutes: 40, remaining: 30)
        let repeating = GroupJoin.canJoin(linkedToEvent: true, oneTime: false, minutes: 10, remaining: 30)
        let timeless = GroupJoin.canJoin(linkedToEvent: true, oneTime: true, minutes: nil, remaining: 0)
        let german = line == "Einmalig - 20 Minuten"
            && weekly == "Wöchentlich - 30 Minuten"
            && bare == "Täglich"
            && zero == "Einmalig"
        let english = line == "Once - 20 minutes"
            && weekly == "Weekly - 30 minutes"
            && bare == "Daily"
            && zero == "Once"
        let passed = (german || english) && open && fits && !full && !repeating && timeless
        let reading = "\(line), \(open && fits ? "offen" : "zu"), \(full ? "leer" : "voll")"
        return result("Einmalig und die Dauer stehen in einer Zeile", .challenge, .unit, passed, reading)
    }

    private static func oldChallengesAreSuggested() -> LififyCheckResult {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-(8 * 86_400))
        let fresh = now.addingTimeInterval(-(2 * 86_400))
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        ]
        let finished = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let suggested = ChallengeTimeRules.offeredSuggestions(
            candidates: [
                (id: ids[1], minutes: nil, createdAt: fresh, offered: true, finished: false),
                (id: ids[0], minutes: 90, createdAt: old, offered: true, finished: false),
                (id: finished, minutes: 15, createdAt: old.addingTimeInterval(-86_400), offered: true, finished: true),
                (id: ids[2], minutes: 10, createdAt: old.addingTimeInterval(-2 * 86_400), offered: false, finished: false)
            ],
            already: []
        )
        let passed = suggested == [ids[0], ids[1]]
        return result("Vorschläge beginnen bei der ältesten Challenge", .challenge, .unit, passed, "\(suggested.count)")
    }

    private static func briefingNamesTheDay() -> LififyCheckResult {
        let text = DailyBriefing.text(
            events: [DailyBriefingLine(title: "Fokus", detail: "10:00")],
            challenges: [DailyBriefingLine(title: "Lesen", detail: "+10")],
            rewards: [DailyBriefingLine(title: "Kino", detail: "200 · 3d")],
            salary: "25.11.",
            expenses: [DailyBriefingLine(title: "Miete", detail: "800 €")]
        )
        let early = DailyBriefing.shouldDeliverBonusNow(
            due: Date(timeIntervalSince1970: 2_000),
            realNow: Date(timeIntervalSince1970: 1_000),
            alreadyQueued: true
        )
        let queued = DailyBriefing.shouldDeliverBonusNow(
            due: Date(timeIntervalSince1970: 1_000),
            realNow: Date(timeIntervalSince1970: 2_000),
            alreadyQueued: true
        )
        let missed = DailyBriefing.shouldDeliverBonusNow(
            due: Date(timeIntervalSince1970: 1_000),
            realNow: Date(timeIntervalSince1970: 2_000),
            alreadyQueued: false
        )
        let passed = text.contains("Fokus") && text.contains("Lesen") && text.contains("Kino")
            && text.contains("25.11.") && text.contains("Miete")
            && early && !queued && missed
        return result("Das Tagesbriefing nennt Termine, Coins, Belohnung, Gehalt und Ausgaben", .challenge, .unit, passed, text)
    }

    private static func todaysAbstinenceNoticeOnly() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)) ?? .distantFuture
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? .distantPast
        let challenge = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let other = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let notices = [
            AbstinenceNotice(id: "old", challengeID: challenge, title: "Rauchfrei", milestone: "24h", coins: 20, date: yesterday),
            AbstinenceNotice(id: "early", challengeID: challenge, title: "Rauchfrei", milestone: "1h", coins: 5, date: today),
            AbstinenceNotice(id: "year", challengeID: challenge, title: "Rauchfrei", milestone: "1y", coins: 100, date: today.addingTimeInterval(3_600)),
            AbstinenceNotice(id: "other", challengeID: other, title: "Zuckerfrei", milestone: "7d", coins: 40, date: today)
        ]
        let shown = AbstinenceRules.currentNotices(notices, on: today, calendar: calendar)
        let cheer = AbstinenceCheer.body(challenge: "Rauchfrei", milestone: .hour24, coins: 20)
        let quiet = AbstinenceCheer.body(challenge: "Rauchfrei", milestone: .hour1, coins: 0)
        let cheerTitle = AbstinenceCheer.title(for: .hour24)
        let passed = shown.map(\.id) == ["early", "other"]
            && cheer.contains("Rauchfrei")
            && (cheer.contains("24 Stunden") || cheer.contains("24 hours"))
            && cheer.contains("20")
            && (cheerTitle == "Ein ganzer Tag!" || cheerTitle == "A whole day!")
            && !quiet.contains("+")
        return result(
            "Auf der Startseite steht nur der Abstinenz-Bonus von heute",
            .abstinence,
            .unit,
            passed,
            "\(shown.map(\.id).joined(separator: ",")), \(cheerTitle)"
        )
    }

    private static func openChallengesGetEveningAndClock() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)) ?? .distantFuture
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 16)) ?? .distantFuture
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let clocks = ChallengeNudgePlan.clocks(
            from: [
                calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 18, minute: 30)) ?? .distantPast,
                calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 20, minute: 0)) ?? .distantPast
            ],
            calendar: calendar
        )
        let requests = ChallengeNudgePlan.requests(
            days: [ChallengeNudgeDay(day: day, items: [ChallengeNudgeItem(id: id, title: "Lesen", clocks: clocks)])],
            now: now,
            calendar: calendar
        )
        let evening = requests.first { $0.id.contains("evening") }
        let clock = requests.first { $0.id.contains("clock") }
        let eveningParts = evening.map { calendar.dateComponents([.hour, .minute], from: $0.fire) }
        let clockParts = clock.map { calendar.dateComponents([.hour, .minute], from: $0.fire) }
        let passed = clocks == [NudgeClock(hour: 18, minute: 30), NudgeClock(hour: 20, minute: 0)]
            && requests.count == 2
            && eveningParts?.hour == 20
            && eveningParts?.minute == 0
            && clockParts?.hour == 18
            && clockParts?.minute == 30
            && (evening?.title == "Noch offen" || evening?.title == "Still open")
            && (clock?.body.contains("18:30") == true)
            && !requests.contains { $0.id.contains("clock") && $0.id.hasSuffix(".20.0") }
        return result(
            "Offene Challenges bekommen einen Abendstups und die Uhrzeit",
            .challenge,
            .unit,
            passed,
            requests.map(\.id).joined(separator: ", ")
        )
    }

    private static func streakWarningAndBirthdayFollowTheClock() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12)) ?? .distantFuture
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12)) ?? .distantFuture
        let monthEnd = calendar.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 10)) ?? .distantFuture
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let warning = ChallengeNudgePlan.streakWarning(
            id: id,
            title: "Lesen",
            streak: 4,
            atRisk: true,
            recurrence: .weekly,
            on: sunday,
            now: sunday,
            calendar: calendar
        )
        let tooEarly = ChallengeNudgePlan.streakWarning(
            id: id,
            title: "Lesen",
            streak: 4,
            atRisk: true,
            recurrence: .weekly,
            on: monday,
            now: monday,
            calendar: calendar
        )
        let quiet = ChallengeNudgePlan.streakWarning(
            id: id,
            title: "Lesen",
            streak: 4,
            atRisk: false,
            recurrence: .daily,
            on: sunday,
            now: sunday,
            calendar: calendar
        )
        let birth = Birthday(year: 1990, month: 11, day: 20)
        let before = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8)) ?? .distantPast
        let after = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10)) ?? .distantFuture
        let next = BirthdayCheer.nextFire(birth: birth, awardedYear: nil, now: before, calendar: calendar)
        let following = BirthdayCheer.nextFire(birth: birth, awardedYear: 2026, now: after, calendar: calendar)
        let nextParts = next.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        let followingParts = following.map { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        let cheer = BirthdayCheer.body()
        let passed = ChallengeNudgePlan.endsToday(recurrence: .daily, on: monday, calendar: calendar)
            && ChallengeNudgePlan.endsToday(recurrence: .weekly, on: sunday, calendar: calendar)
            && !ChallengeNudgePlan.endsToday(recurrence: .weekly, on: monday, calendar: calendar)
            && ChallengeNudgePlan.endsToday(recurrence: .monthly, on: monthEnd, calendar: calendar)
            && warning != nil
            && tooEarly == nil
            && quiet == nil
            && (warning?.body.contains("4") == true)
            && (warning?.title == "Serie in Gefahr" || warning?.title == "Streak at risk")
            && nextParts?.year == 2026
            && nextParts?.month == 11
            && nextParts?.day == 20
            && nextParts?.hour == 9
            && nextParts?.minute == 0
            && followingParts?.year == 2027
            && followingParts?.month == 11
            && followingParts?.day == 20
            && followingParts?.hour == 9
            && cheer.contains("500")
            && (BirthdayCheer.title() == "Alles Gute!" || BirthdayCheer.title() == "Happy birthday!")
        return result(
            "Eine Serie wird nur am letzten Tag gewarnt",
            .challenge,
            .integration,
            passed,
            "\(warning?.title ?? "keine"), \(cheer)"
        )
    }

    private static func recentEventsCanBeAssigned() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12)) ?? .now
        let older = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8)) ?? .distantPast
        let sameDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 19)) ?? .now
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 8)) ?? .distantFuture
        let anchor = ChallengeTimeRules.pickerAnchor(
            eventStarts: [later, older, sameDay],
            today: today,
            calendar: calendar
        )
        let closed = ChallengeTimeRules.canOffer(
            exclusive: true,
            slotMinutes: 90,
            linkedMinutes: [],
            keepingSelection: false
        )
        let full = ChallengeTimeRules.canOffer(
            exclusive: false,
            slotMinutes: 90,
            linkedMinutes: [60, 30],
            keepingSelection: false
        )
        let open = ChallengeTimeRules.canOffer(
            exclusive: false,
            slotMinutes: 90,
            linkedMinutes: [30],
            keepingSelection: false
        )
        let untimed = ChallengeTimeRules.canOffer(
            exclusive: false,
            slotMinutes: 90,
            linkedMinutes: [],
            keepingSelection: false
        )
        let kept = ChallengeTimeRules.canOffer(
            exclusive: true,
            slotMinutes: 90,
            linkedMinutes: [90],
            keepingSelection: true
        )
        let passed = anchor == 1
            && !closed
            && !full
            && open
            && untimed
            && kept
            && ChallengeTimeRules.isExclusiveLink(category: .sport, identifier: nil)
            && ChallengeTimeRules.isExclusiveLink(category: .abstinence, identifier: nil)
            && ChallengeTimeRules.isExclusiveLink(category: .other, identifier: "event-challenge:gym")
            && !ChallengeTimeRules.isExclusiveLink(category: .other, identifier: nil)
        let reading = "\(anchor), \(closed ? "auf" : "zu")"
        return result("Die Terminauswahl öffnet beim heutigen Tag", .challenge, .unit, passed, reading)
    }

    private static func linkingSetsTheChallengeDay() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let eventStart = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 19, minute: 15)) ?? .now
        let earlier = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)) ?? .distantPast
        let placed = EventChallengeLink.placement(
            eventStart: eventStart,
            recurrence: .weekly,
            weekdays: [2],
            end: earlier,
            calendar: calendar
        )
        let weekday = calendar.component(.weekday, from: eventStart)
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        let late = UUID(uuidString: "00000000-0000-0000-0000-000000000043")!
        let members = EventChallengeLink.members(already: [first, second], linked: nil, adding: late)
        let passed = placed.start == eventStart
            && placed.weekdays == [weekday]
            && placed.end == nil
            && members == [first, second, late]
            && EventChallengeLink.makesGroup(count: members.count)
            && !EventChallengeLink.makesGroup(count: 1)
            && EventChallengeLink.reminderIncludesTime(allDay: false)
            && !EventChallengeLink.reminderIncludesTime(allDay: true)
        let reading = "19:15, \(members.count)"
        return result("Ein Termin setzt den Tag der Challenge", .challenge, .unit, passed, reading)
    }

    private static func categoriesSplitTheActiveList() -> LififyCheckResult {
        let separate = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let pooled = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let abstinence = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
        let sport = UUID(uuidString: "00000000-0000-0000-0000-000000000024")!
        let habit = UUID(uuidString: "00000000-0000-0000-0000-000000000025")!
        let sections = ChallengeSections.make(
            challenges: [
                .init(id: habit, categoryRaw: "habit"),
                .init(id: abstinence, categoryRaw: ChallengeCategory.abstinence.rawValue),
                .init(id: sport, categoryRaw: ChallengeCategory.sport.rawValue),
                .init(id: separate, categoryRaw: "custom:\(separate.uuidString)"),
                .init(id: pooled, categoryRaw: "custom:\(pooled.uuidString)")
            ],
            customs: [
                .init(id: separate, name: "Fokus", separate: true),
                .init(id: pooled, name: "Lesen", separate: false)
            ]
        )
        let passed = sections.map(\.id) == ["abstinence", "sport", separate.uuidString, "rest"]
            && sections[0].challengeIDs == [abstinence]
            && sections[1].challengeIDs == [sport]
            && sections[3].challengeIDs == [habit, pooled]
            && sections[3].showsTitle
        return result("Sport und Abstinenz stehen separat, der Rest in einem Topf", .challenge, .unit, passed, sections.map(\.id).joined(separator: ","))
    }

    private static func briefingClockFollowsTheWeekday() -> LififyCheckResult {
        let monday = BriefingSchedule.clock(weekday: 2, overrides: [2: BriefingClock(hour: 7, minute: 30)], fallback: BriefingClock(hour: 8, minute: 0))
        let sunday = BriefingSchedule.clock(weekday: 1, overrides: [:], fallback: BriefingClock(hour: 8, minute: 0))
        let late = BriefingSchedule.clock(weekday: 6, overrides: [6: BriefingClock(hour: 25, minute: 70)], fallback: BriefingClock(hour: 8, minute: 0))
        let passed = monday == BriefingClock(hour: 7, minute: 30)
            && sunday == BriefingClock(hour: 8, minute: 0)
            && late == BriefingClock(hour: 23, minute: 59)
            && BriefingSchedule.weekdays == [2, 3, 4, 5, 6, 7, 1]
        return result("Das Briefing hat von Montag bis Sonntag eine eigene Uhrzeit", .challenge, .unit, passed, "\(monday.hour):\(monday.minute)")
    }

    private static func shopTilesShareARow() -> LififyCheckResult {
        let rows = ShopRows.pairs([1, 2, 3, 4, 5])
        let passed = rows.count == 3 && rows[0] == [1, 2] && rows[1] == [3, 4] && rows[2] == [5]
        return result("Zwei Shop-Kacheln teilen sich eine Reihe", .challenge, .unit, passed, "\(rows.count)")
    }

    private static func abstinenceHistoryStaysOneRow() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let abstinence = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let habit = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 8)) ?? .distantPast
        let middle = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8)) ?? .distantPast
        let last = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8)) ?? .distantPast
        let rows = [
            ChallengeHistoryCompletion(challengeID: abstinence, title: "Rauchfrei", date: first),
            ChallengeHistoryCompletion(challengeID: abstinence, title: "Rauchfrei", date: middle),
            ChallengeHistoryCompletion(challengeID: abstinence, title: "Rauchfrei", date: last),
            ChallengeHistoryCompletion(challengeID: habit, title: "Lesen", date: middle)
        ]
        let spans = ChallengeHistory.abstinenceSpans(rows.filter { $0.challengeID == abstinence }, calendar: calendar)
        let days = ChallengeHistory.grouped(completions: rows.filter { $0.challengeID != abstinence }, calendar: calendar)
        let passed = spans.count == 1
            && spans[0].dayCount == 3
            && spans[0].first == calendar.startOfDay(for: first)
            && spans[0].last == calendar.startOfDay(for: last)
            && days.count == 1
            && days[0].entries.map(\.title) == ["Lesen"]
        return result("Eine Abstinenz steht unter Abgeschlossen als ein Eintrag", .abstinence, .integration, passed, "\(spans.count)")
    }

    private static func birthdayPaysFiveHundredOnce() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let birth = Birthday(year: 1990, month: 11, day: 8)
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 15)) ?? .distantPast
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 15)) ?? .distantPast
        let leapBirth = Birthday(year: 2000, month: 2, day: 29)
        let ordinaryFebruary = calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12)) ?? .distantPast
        let leapEve = calendar.date(from: DateComponents(year: 2028, month: 2, day: 28, hour: 12)) ?? .distantPast
        let leapDay = calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 12)) ?? .distantPast
        let beforeBirth = calendar.date(from: DateComponents(year: 1989, month: 11, day: 8, hour: 12)) ?? .distantPast
        let passed = BirthdayBonus.coins == 500
            && BirthdayBonus.isDue(birth: birth, on: today, awardedYear: nil, calendar: calendar)
            && !BirthdayBonus.isDue(birth: birth, on: today, awardedYear: 2026, calendar: calendar)
            && !BirthdayBonus.isDue(birth: birth, on: tomorrow, awardedYear: nil, calendar: calendar)
            && BirthdayBonus.isDue(birth: leapBirth, on: ordinaryFebruary, awardedYear: nil, calendar: calendar)
            && !BirthdayBonus.isDue(birth: leapBirth, on: leapEve, awardedYear: nil, calendar: calendar)
            && BirthdayBonus.isDue(birth: leapBirth, on: leapDay, awardedYear: nil, calendar: calendar)
            && !BirthdayBonus.isDue(birth: birth, on: beforeBirth, awardedYear: nil, calendar: calendar)
            && BirthdayBonus.referenceID(year: 2026) == BirthdayBonus.referenceID(year: 2026)
        return result("Geburtstag zahlt 500 Coins einmal an diesem Tag", .challenge, .unit, passed, "heute \(BirthdayBonus.isDue(birth: birth, on: today, awardedYear: nil, calendar: calendar))")
    }

    private static func birthdayFollowsTheYear() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let birth = Birthday(year: 1990, month: 11, day: 8)
        let before = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9)) ?? .distantPast
        let onDay = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9)) ?? .distantPast
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 11, day: 8, hour: 9)) ?? .distantPast
        let passed = !BirthdayBonus.isDue(birth: birth, on: before, awardedYear: nil, calendar: calendar)
            && BirthdayBonus.isDue(birth: birth, on: onDay, awardedYear: nil, calendar: calendar)
            && !BirthdayBonus.isDue(birth: birth, on: onDay, awardedYear: 2026, calendar: calendar)
            && BirthdayBonus.isDue(birth: birth, on: nextYear, awardedYear: 2026, calendar: calendar)
            && BirthdayBonus.isBirthday(birth, on: onDay, calendar: calendar)
        return result("Der Geburtstagsbonus gilt im nächsten Jahr wieder", .challenge, .integration, passed, "nächstes Jahr \(BirthdayBonus.isDue(birth: birth, on: nextYear, awardedYear: 2026, calendar: calendar))")
    }

    private static func result(
        _ name: String,
        _ topic: LififyCheckTopic,
        _ kind: LififyCheckKind,
        _ passed: Bool,
        _ detail: String
    ) -> LififyCheckResult {
        LififyCheckResult(name: name, passed: passed, detail: passed ? nil : detail, reading: detail, kind: kind, topic: topic)
    }
}
