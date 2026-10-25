import Foundation

enum LififyCheckKind: String, Equatable {
    case unit
    case integration
}

struct LififyCheckResult: Identifiable, Equatable {
    var name: String
    var passed: Bool
    var detail: String?
    var kind: LififyCheckKind
    var id: String { name }
}

/// Regression checks for streaks, link captions, and workout links.
/// They only read models in memory and do not write the user's data.
@MainActor
enum LififyChecks {
    static func run() -> [LififyCheckResult] {
        [
            multiplierReplacesLowerStep(),
            challengeCaptionNamesTheChallenge(),
            calendarCaptionNamesTheEntry(),
            developerDayKeepsClockTime(),
            linkingChallengePullsCalendar(),
            linkingEventPullsChallenge(),
            removingChallengeDropsItsEvents(),
            weeklyQuotaWhileOpen(),
            extraDaysStillCount(),
            weeklyQuotaKeepsStreakWithFreeze(),
            weeklyQuotaResetsAfterFreezes(),
            monthlyQuota(),
            dailyStreakCountsEachDay()
        ]
    }

    private static func multiplierReplacesLowerStep() -> LififyCheckResult {
        let atTwelve = StreakSettings.factor(forStreak: 12, configured: [5: 1.1, 10: 1.2])
        let atSeven = StreakSettings.factor(forStreak: 7, configured: [5: 1.1, 10: 1.2])
        let unsetHigher = StreakSettings.factor(forStreak: 12, configured: [5: 1.1])
        let passed = atTwelve == 1.2 && atSeven == 1.1 && unsetHigher == 1.1
        return result("Multiplikator ersetzt die niedrigere Stufe", .unit, passed, "12× \(atTwelve), 7× \(atSeven), ohne 10er \(unsetHigher)")
    }

    private static func challengeCaptionNamesTheChallenge() -> LififyCheckResult {
        let text = LinkCaption.challenge("Gym")
        let passed = text == "Mit Challenge Gym verknüpft" || text == "Linked to challenge Gym"
        return result("Challenge-Name im Kalender", .unit, passed, text)
    }

    private static func calendarCaptionNamesTheEntry() -> LififyCheckResult {
        let when = AppDate.numeric(day(2026, 10, 25))
        let text = LinkCaption.calendar(titles: ["Gym"], count: 1, singleDate: day(2026, 10, 25))
        let passed = text == "Mit Kalender Gym · \(when) verknüpft" || text == "Linked to calendar Gym · \(when)"
        return result("Kalendereintrag in der Challenge", .unit, passed, text ?? "leer")
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
        return result("Entwicklertag behält die Uhrzeit", .unit, passed, "\(parts.day ?? 0).\(parts.month ?? 0). \(parts.hour ?? 0):\(parts.minute ?? 0)")
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
        return result("Challenge zieht ihre Kalendereinträge nach", .unit, passed, "Termine \(next.events.count)")
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
        return result("Kalendereintrag zieht Challenge und Geschwister nach", .unit, passed, "Challenges \(next.challenges.count), Termine \(next.events.count)")
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
            .unit,
            passed,
            "Bleibt \(kept.challenges.count)/\(kept.events.count), leer \(cleared.challenges.count)/\(cleared.events.count)"
        )
    }

    private static func weeklyQuotaWhileOpen() -> LififyCheckResult {
        let status = weeklyStatus(
            eventsOn: [day(2026, 10, 5), day(2026, 10, 7), day(2026, 10, 9)],
            completionsOn: [day(2026, 10, 5), day(2026, 10, 8)],
            endingOn: day(2026, 10, 8),
            purchasedFreezes: 0
        )
        let passed = status.count == 2 && status.required == 3 && status.done == 2
        return result("Offene Woche zählt beliebige Tage", .integration, passed, "Serie \(status.count), \(status.done)/\(status.required)")
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
        return result("Mehr Tage als die Woche verlangt zählen mit", .integration, passed, "Serie \(status.count), \(status.done)/\(status.required)")
    }

    private static func weeklyQuotaKeepsStreakWithFreeze() -> LififyCheckResult {
        let status = weeklyStatus(
            eventsOn: [day(2026, 10, 5), day(2026, 10, 7), day(2026, 10, 9)],
            completionsOn: [day(2026, 10, 5), day(2026, 10, 8)],
            endingOn: day(2026, 10, 12),
            purchasedFreezes: 0
        )
        let passed = status.count == 2 && status.freezeKeys.count == 1
        return result("Freeze hält die angefangene Serie", .integration, passed, "Serie \(status.count), Freezes verbraucht \(status.freezeKeys.count)")
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
        return result("Dritte verpasste Woche setzt die Serie auf 0", .integration, passed, "Serie \(status.count), Freezes verbraucht \(status.freezeKeys.count)")
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
        return result("Tägliche Serie zählt jeden Tag", .integration, passed, "Serie \(status.count), heute \(status.done)/\(status.required)")
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

    private static func result(_ name: String, _ kind: LififyCheckKind, _ passed: Bool, _ detail: String) -> LififyCheckResult {
        LififyCheckResult(name: name, passed: passed, detail: passed ? nil : detail, kind: kind)
    }
}
