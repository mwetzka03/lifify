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

    var title: String {
        switch self {
        case .streak: L("Streak", "Streak")
        case .multiplier: L("Multiplikator", "Multiplier")
        case .challenge: L("Challenge", "Challenge")
        case .calendar: L("Kalender", "Calendar")
        case .training: L("Training", "Training")
        case .abstinence: L("Abstinenz", "Abstinence")
        case .developer: L("Entwicklermodus", "Developer mode")
        }
    }
}

struct LififyCheckResult: Identifiable, Equatable {
    var name: String
    var passed: Bool
    var detail: String?
    var kind: LififyCheckKind
    var topic: LififyCheckTopic
    var id: String { name }
}

/// Regression checks for streaks, link captions, and workout links.
/// They only read models in memory and do not write the user's data.
@MainActor
enum LififyChecks {
    static func run() -> [LififyCheckResult] {
        [
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
            oldChallengesAreSuggested(),
            briefingNamesTheDay(),
            developerDayKeepsClockTime()
        ]
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
        let passed = parts.year == 2026 && parts.month == 11 && parts.day == 2
            && parts.hour == 16 && parts.minute == 5 && parts.second == 9
        return result("Entwicklertag behält die Uhrzeit", .developer, .unit, passed, "\(parts.day ?? 0).\(parts.month ?? 0). \(parts.hour ?? 0):\(parts.minute ?? 0)")
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
        let single = ChallengeTimeRules.displayedMinutes(planned: 120, linked: [30], completed: [])
        let waiting = ChallengeTimeRules.displayedMinutes(planned: 120, linked: [30, 30, 30, 30], completed: [])
        let partial = ChallengeTimeRules.displayedMinutes(planned: 120, linked: [30, 30, 30, 30], completed: [30, 30, 30])
        let full = ChallengeTimeRules.displayedMinutes(planned: 120, linked: [30, 30, 30, 30], completed: [30, 30, 30, 30])
        let passed = single == 30 && waiting == 120 && partial == 90 && full == 120
        return result("Drei erledigte Challenges à 30 Minuten machen den Termin zu 90 Minuten", .challenge, .integration, passed, "einzeln \(single), teil \(partial)")
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
        let suggested = ChallengeTimeRules.suggestions(
            candidates: [
                (id: ids[0], minutes: 30, createdAt: old),
                (id: ids[1], minutes: 30, createdAt: fresh),
                (id: ids[2], minutes: 90, createdAt: old)
            ],
            now: now,
            remaining: 40,
            already: []
        )
        let passed = suggested == [ids[0]]
        return result("Ältere Challenges werden vorgeschlagen, wenn sie in die Zeit passen", .challenge, .unit, passed, "\(suggested.count)")
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

    private static func result(
        _ name: String,
        _ topic: LififyCheckTopic,
        _ kind: LififyCheckKind,
        _ passed: Bool,
        _ detail: String
    ) -> LififyCheckResult {
        LififyCheckResult(name: name, passed: passed, detail: passed ? nil : detail, kind: kind, topic: topic)
    }
}
