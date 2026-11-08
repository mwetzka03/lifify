import Foundation

struct NudgeClock: Equatable, Hashable {
    var hour: Int
    var minute: Int
}

struct ChallengeNudgeRequest: Equatable, Identifiable {
    var id: String
    var title: String
    var body: String
    var fire: Date
}

struct ChallengeNudgeDay: Equatable {
    var day: Date
    var items: [ChallengeNudgeItem]
}

struct ChallengeNudgeItem: Equatable, Identifiable {
    var id: UUID
    var title: String
    var clocks: [NudgeClock]
}

/// Evening nudge, clock-time nudge, and the last-day streak warning.
/// The plan only builds requests. It does not read or write stored data.
enum ChallengeNudgePlan {
    static let nudgePrefix = "lifify.nudge."
    static let birthdayPrefix = "lifify.birthday."
    static let evening = NudgeClock(hour: 20, minute: 0)
    static let streakHour = 18

    static func clocks(from starts: [Date], calendar: Calendar) -> [NudgeClock] {
        var seen: [NudgeClock] = []
        for start in starts {
            let clock = NudgeClock(
                hour: calendar.component(.hour, from: start),
                minute: calendar.component(.minute, from: start)
            )
            if !seen.contains(clock) { seen.append(clock) }
        }
        return seen
    }

    /// One evening nudge, plus each linked clock that is not the same minute.
    static func requests(days: [ChallengeNudgeDay], now: Date, calendar: Calendar) -> [ChallengeNudgeRequest] {
        var result: [ChallengeNudgeRequest] = []
        for plan in days {
            let stamp = dayStamp(plan.day, calendar: calendar)
            for item in plan.items {
                if let fire = fire(on: plan.day, clock: evening, calendar: calendar), fire > now {
                    result.append(ChallengeNudgeRequest(
                        id: "\(nudgePrefix)evening.\(item.id.uuidString).\(stamp)",
                        title: L("Noch offen", "Still open"),
                        body: L(
                            "\(item.title) wartet noch auf den Haken.",
                            "\(item.title) is still waiting for a check."
                        ),
                        fire: fire
                    ))
                }
                var seen: Set<NudgeClock> = []
                for clock in item.clocks where clock != evening && seen.insert(clock).inserted {
                    guard let fire = fire(on: plan.day, clock: clock, calendar: calendar), fire > now else { continue }
                    let time = String(format: "%02d:%02d", clock.hour, clock.minute)
                    result.append(ChallengeNudgeRequest(
                        id: "\(nudgePrefix)clock.\(item.id.uuidString).\(stamp).\(clock.hour).\(clock.minute)",
                        title: L("Es ist soweit", "It's time"),
                        body: L(
                            "\(item.title) ist um \(time) noch offen.",
                            "\(item.title) is still open at \(time)."
                        ),
                        fire: fire
                    ))
                }
            }
        }
        return result
    }

    /// Weeks run Monday through Sunday, the same split the streak uses.
    static func endsToday(recurrence: ChallengeRecurrence, on date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        switch recurrence {
        case .daily:
            return true
        case .weekly:
            return calendar.component(.weekday, from: day) == 1
        case .monthly:
            guard let range = calendar.range(of: .day, in: .month, for: day) else { return false }
            return calendar.component(.day, from: day) == range.count
        case .yearly:
            let parts = calendar.dateComponents([.month, .day], from: day)
            return parts.month == 12 && parts.day == 31
        case .none, .irregular:
            return false
        }
    }

    static func streakWarning(
        id: UUID,
        title: String,
        streak: Int,
        atRisk: Bool,
        recurrence: ChallengeRecurrence,
        on date: Date,
        now: Date,
        calendar: Calendar
    ) -> ChallengeNudgeRequest? {
        guard atRisk, streak > 0, endsToday(recurrence: recurrence, on: date, calendar: calendar) else { return nil }
        let clock = NudgeClock(hour: streakHour, minute: 0)
        guard let fire = fire(on: date, clock: clock, calendar: calendar), fire > now else { return nil }
        return ChallengeNudgeRequest(
            id: "\(nudgePrefix)streak.\(id.uuidString).\(dayStamp(date, calendar: calendar))",
            title: L("Serie in Gefahr", "Streak at risk"),
            body: L(
                "\(title): \(streak) in Folge. Heute fehlt der Haken, sonst reißt die Serie.",
                "\(title): \(streak) in a row. Today still needs a check, or the streak breaks."
            ),
            fire: fire
        )
    }

    private static func fire(on day: Date, clock: NudgeClock, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
    }

    private static func dayStamp(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum BirthdayCheer {
    static let fireHour = 9
    static let fireMinute = 0

    static func title() -> String { L("Alles Gute!", "Happy birthday!") }

    static func body() -> String {
        L("500 Coins liegen für dich bereit.", "500 coins are waiting for you.")
    }

    /// The next observed birthday at 9:00 that is still ahead and not already awarded.
    static func nextFire(birth: Birthday, awardedYear: Int?, now: Date, calendar: Calendar) -> Date? {
        let startYear = calendar.component(.year, from: now)
        guard let born = BirthdayBonus.observed(birth: birth, in: birth.year, calendar: calendar) else { return nil }
        for year in startYear...(startYear + 1) {
            if awardedYear == year { continue }
            guard let observed = BirthdayBonus.observed(birth: birth, in: year, calendar: calendar),
                  observed >= born
            else { continue }
            guard let fire = calendar.date(bySettingHour: fireHour, minute: fireMinute, second: 0, of: observed),
                  fire > now
            else { continue }
            return fire
        }
        return nil
    }
}
