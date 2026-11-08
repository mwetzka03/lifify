import Foundation

/// Developer override for the day Home, challenges, and the calendar call today.
/// The calendar day follows the device time zone, the way Apple keeps a picked date.
/// Developer mode still replaces that day and keeps the real clock time.
enum AppClock {
    static let modeKey = "lifify.developerMode"
    static let dayKey = "lifify.developerDay"
    static let dayStampKey = "lifify.developerDayStamp"

    static var isDeveloperMode: Bool {
        UserDefaults.standard.bool(forKey: modeKey)
    }

    static var now: Date {
        let clock = Date()
        guard isDeveloperMode else { return clock }
        let zone = Calendar.autoupdatingCurrent
        if let stamp = storedStamp(), let combined = combining(stamp: stamp, time: clock, calendar: zone) {
            return combined
        }
        let stored = UserDefaults.standard.double(forKey: dayKey)
        guard stored > 0 else { return clock }
        return combining(day: Date(timeIntervalSince1970: stored), time: clock, calendar: zone)
    }

    static func stamp(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Applies a stored calendar day in the given time zone and keeps that zone's clock time.
    static func combining(stamp: String, time: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
        let pieces = stamp.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2])
        else { return nil }
        let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = clock.second
        return calendar.date(from: parts)
    }

    static func stamp(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return stamp(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
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
        let zone = Calendar.autoupdatingCurrent
        if let stamp = storedStamp(),
           let date = combining(stamp: stamp, time: zone.startOfDay(for: Date()), calendar: zone) {
            return zone.startOfDay(for: date)
        }
        let stored = UserDefaults.standard.double(forKey: dayKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        return zone.startOfDay(for: Date())
    }

    /// Stores the calendar day, not a midnight instant, so a time-zone change does not shift it.
    static func setSimulatedDay(_ date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let stamp = stamp(for: date, calendar: calendar)
        UserDefaults.standard.set(stamp, forKey: dayStampKey)
        UserDefaults.standard.set(calendar.startOfDay(for: date).timeIntervalSince1970, forKey: dayKey)
    }

    /// Puts the simulated day back on the real today. Used at launch and when the mode is switched.
    static func resetSimulatedDay(calendar: Calendar = .autoupdatingCurrent) {
        setSimulatedDay(Date(), calendar: calendar)
    }

    /// Rewrites the stored instant after the device time zone changes, and keeps the chosen day.
    static func rebaseSimulatedDayToCurrentTimeZone() {
        let zone = Calendar.autoupdatingCurrent
        guard let stamp = storedStamp(),
              let date = combining(stamp: stamp, time: Date(), calendar: zone)
        else { return }
        UserDefaults.standard.set(zone.startOfDay(for: date).timeIntervalSince1970, forKey: dayKey)
    }

    private static func storedStamp() -> String? {
        if let stamp = UserDefaults.standard.string(forKey: dayStampKey), !stamp.isEmpty {
            return stamp
        }
        let stored = UserDefaults.standard.double(forKey: dayKey)
        guard stored > 0 else { return nil }
        return stamp(for: Date(timeIntervalSince1970: stored))
    }
}
