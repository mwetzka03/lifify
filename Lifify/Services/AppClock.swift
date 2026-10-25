import Foundation

/// Developer override for the day Home, challenges, and the calendar call today.
enum AppClock {
    static let modeKey = "lifify.developerMode"
    static let dayKey = "lifify.developerDay"

    static var isDeveloperMode: Bool {
        UserDefaults.standard.bool(forKey: modeKey)
    }

    static var now: Date {
        let clock = Date()
        guard isDeveloperMode else { return clock }
        let stored = UserDefaults.standard.double(forKey: dayKey)
        guard stored > 0 else { return clock }
        return combining(day: Date(timeIntervalSince1970: stored), time: clock)
    }

    /// Keeps the clock time and replaces the calendar day. Used by the developer day and by tests.
    static func combining(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = clock.second
        return calendar.date(from: parts) ?? time
    }

    static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    static var simulatedDay: Date {
        let stored = UserDefaults.standard.double(forKey: dayKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        return Calendar.current.startOfDay(for: Date())
    }
}
