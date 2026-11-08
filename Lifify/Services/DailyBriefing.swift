import Foundation

struct DailyBriefingLine: Equatable {
    var title: String
    var detail: String
}

/// The text of the daily push. It only formats values it is given.
enum DailyBriefing {
    static func text(
        events: [DailyBriefingLine],
        challenges: [DailyBriefingLine],
        rewards: [DailyBriefingLine],
        salary: String?,
        expenses: [DailyBriefingLine]
    ) -> String {
        var lines: [String] = []
        if !events.isEmpty {
            lines.append(labeled(L("Termine", "Events"), events))
        }
        if !challenges.isEmpty {
            lines.append(labeled(L("Challenges", "Challenges"), challenges))
        }
        if !rewards.isEmpty {
            lines.append(labeled(L("Belohnungen", "Rewards"), rewards))
        }
        if let salary, !salary.isEmpty {
            lines.append("\(L("Gehalt", "Salary")): \(salary)")
        }
        if !expenses.isEmpty {
            lines.append(labeled(L("Ausgaben", "Expenses"), expenses))
        }
        if lines.isEmpty {
            return L("Heute steht nichts an.", "Nothing is scheduled today.")
        }
        let joined = lines.joined(separator: "\n")
        if joined.count <= 500 { return joined }
        return String(joined.prefix(497)) + "…"
    }

    /// A bonus reached before real time, or one nobody queued, should notify now.
    static func shouldDeliverBonusNow(due: Date, realNow: Date, alreadyQueued: Bool) -> Bool {
        if due > realNow { return true }
        return !alreadyQueued
    }

    private static func labeled(_ title: String, _ lines: [DailyBriefingLine]) -> String {
        let body = lines.prefix(4).map { line in
            line.detail.isEmpty ? line.title : "\(line.title) \(line.detail)"
        }.joined(separator: ", ")
        return "\(title): \(body)"
    }
}

struct BriefingClock: Equatable {
    var hour: Int
    var minute: Int
}

/// Monday through Sunday, each with its own clock. A missing day uses the fallback.
enum BriefingSchedule {
    static let weekdays = [2, 3, 4, 5, 6, 7, 1]

    static func clock(weekday: Int, overrides: [Int: BriefingClock], fallback: BriefingClock) -> BriefingClock {
        let clock = overrides[weekday] ?? fallback
        return BriefingClock(
            hour: min(max(clock.hour, 0), 23),
            minute: min(max(clock.minute, 0), 59)
        )
    }

    static func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 2: L("Montag", "Monday")
        case 3: L("Dienstag", "Tuesday")
        case 4: L("Mittwoch", "Wednesday")
        case 5: L("Donnerstag", "Thursday")
        case 6: L("Freitag", "Friday")
        case 7: L("Samstag", "Saturday")
        case 1: L("Sonntag", "Sunday")
        default: ""
        }
    }
}
