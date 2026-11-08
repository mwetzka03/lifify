import Foundation

/// How demanding an abstinence is. Harder ones pay a larger bonus.
enum AbstinenceDifficulty: String, CaseIterable, Identifiable, Equatable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: L("Leicht", "Easy")
        case .medium: L("Mittel", "Medium")
        case .hard: L("Schwer", "Hard")
        }
    }
}

/// Bonus steps. Hours are exact durations. Days and the year follow the calendar.
enum AbstinenceMilestone: String, CaseIterable, Identifiable, Equatable {
    case hour1 = "1h"
    case hour2 = "2h"
    case hour4 = "4h"
    case hour8 = "8h"
    case hour24 = "24h"
    case hour72 = "72h"
    case day7 = "7d"
    case day14 = "14d"
    case day30 = "30d"
    case year1 = "1y"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour1: L("1 Stunde", "1 hour")
        case .hour2: L("2 Stunden", "2 hours")
        case .hour4: L("4 Stunden", "4 hours")
        case .hour8: L("8 Stunden", "8 hours")
        case .hour24: L("24 Stunden", "24 hours")
        case .hour72: L("72 Stunden", "72 hours")
        case .day7: L("7 Tage", "7 days")
        case .day14: L("14 Tage", "14 days")
        case .day30: L("30 Tage", "30 days")
        case .year1: L("1 Jahr", "1 year")
        }
    }

    func due(from start: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour1: return start.addingTimeInterval(3_600)
        case .hour2: return start.addingTimeInterval(2 * 3_600)
        case .hour4: return start.addingTimeInterval(4 * 3_600)
        case .hour8: return start.addingTimeInterval(8 * 3_600)
        case .hour24: return start.addingTimeInterval(24 * 3_600)
        case .hour72: return start.addingTimeInterval(72 * 3_600)
        case .day7: return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .day14: return calendar.date(byAdding: .day, value: 14, to: start) ?? start
        case .day30: return calendar.date(byAdding: .day, value: 30, to: start) ?? start
        case .year1: return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }
}

struct AbstinenceClock: Equatable {
    var days: Int
    var hours: Int
    var minutes: Int
    var seconds: Int
}

struct AbstinenceAwardPlan: Equatable {
    var days: [Date]
    var milestones: [AbstinenceMilestone]
}

/// Pure timer, daily coins, and bonus steps. Nothing here reads or writes stored data.
enum AbstinenceRules {
    static let defaultMultipliers: [AbstinenceDifficulty: [String: Double]] = [
        .easy: [
            "1h": 0.5, "2h": 0.5, "4h": 1, "8h": 1, "24h": 2,
            "72h": 3, "7d": 4, "14d": 5, "30d": 8, "1y": 12
        ],
        .medium: [
            "1h": 2, "2h": 2, "4h": 3, "8h": 4, "24h": 6,
            "72h": 10, "7d": 14, "14d": 20, "30d": 30, "1y": 50
        ],
        .hard: [
            "1h": 4, "2h": 4, "4h": 6, "8h": 8, "24h": 12,
            "72h": 20, "7d": 28, "14d": 40, "30d": 60, "1y": 100
        ]
    ]

    static func elapsed(from start: Date, to now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(start))
    }

    static func clock(_ interval: TimeInterval) -> AbstinenceClock {
        let total = max(0, Int(interval.rounded(.down)))
        return AbstinenceClock(
            days: total / 86_400,
            hours: (total % 86_400) / 3_600,
            minutes: (total % 3_600) / 60,
            seconds: total % 60
        )
    }

    static func bonusCoins(base: Int, multiplier: Double) -> Int {
        guard base > 0, multiplier > 0 else { return 0 }
        return Int((Double(base) * multiplier).rounded())
    }

    static func merging(_ stored: [String: Double], defaults: [String: Double]) -> [String: Double] {
        var map = defaults
        for (key, value) in stored where defaults[key] != nil && value >= 0 {
            map[key] = value
        }
        return map
    }

    static func reached(start: Date, now: Date, calendar: Calendar = .current) -> [AbstinenceMilestone] {
        guard now >= start else { return [] }
        return AbstinenceMilestone.allCases.filter { now >= $0.due(from: start, calendar: calendar) }
    }

    static func dayStarts(from start: Date, through now: Date, calendar: Calendar = .current) -> [Date] {
        guard now >= start else { return [] }
        let last = calendar.startOfDay(for: now)
        var cursor = calendar.startOfDay(for: start)
        var days: [Date] = []
        var guardCount = 0
        while cursor <= last && guardCount < 4_000 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCount += 1
        }
        return days
    }

    /// Days that still need the base coins, and bonus steps not yet paid for this run.
    static func plan(
        start: Date,
        now: Date,
        completedDays: Set<Date>,
        awarded: Set<String>,
        calendar: Calendar = .current
    ) -> AbstinenceAwardPlan {
        let days = dayStarts(from: start, through: now, calendar: calendar).filter { !completedDays.contains($0) }
        let milestones = reached(start: start, now: now, calendar: calendar).filter { !awarded.contains($0.rawValue) }
        return AbstinenceAwardPlan(days: days, milestones: milestones)
    }
}
