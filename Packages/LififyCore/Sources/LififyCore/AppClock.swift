import Foundation

/// Developer override for the day Home, challenges, and the calendar call today.
/// The calendar day follows the device time zone, the way Apple keeps a picked date.
/// Developer mode still replaces that day and keeps the real clock time.
public enum AppClock {
    public static let modeKey = "lifify.developerMode"
    public static let dayKey = "lifify.developerDay"
    public static let dayStampKey = "lifify.developerDayStamp"

    public static var isDeveloperMode: Bool {
        AppDefaults.store.bool(forKey: modeKey)
    }

    public static var now: Date {
        let clock = Date()
        guard isDeveloperMode else { return clock }
        let zone = Calendar.autoupdatingCurrent
        if let stamp = storedStamp(), let combined = combining(stamp: stamp, time: clock, calendar: zone) {
            return combined
        }
        let stored = AppDefaults.store.double(forKey: dayKey)
        guard stored > 0 else { return clock }
        return combining(day: Date(timeIntervalSince1970: stored), time: clock, calendar: zone)
    }

    public static func stamp(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Applies a stored calendar day in the given time zone and keeps that zone's clock time.
    public static func combining(stamp: String, time: Date, calendar: Calendar = .autoupdatingCurrent) -> Date? {
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

    public static func stamp(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return stamp(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Keeps the clock time and replaces the calendar day. Used by the developer day and by tests.
    public static func combining(day: Date, time: Date, calendar: Calendar = .current) -> Date {
        let clock = calendar.dateComponents([.hour, .minute, .second], from: time)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = clock.second
        return calendar.date(from: parts) ?? time
    }

    public static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    public static var simulatedDay: Date {
        let zone = Calendar.autoupdatingCurrent
        if let stamp = storedStamp(),
           let date = combining(stamp: stamp, time: zone.startOfDay(for: Date()), calendar: zone) {
            return zone.startOfDay(for: date)
        }
        let stored = AppDefaults.store.double(forKey: dayKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        return zone.startOfDay(for: Date())
    }

    /// Stores the calendar day, not a midnight instant, so a time-zone change does not shift it.
    public static func setSimulatedDay(_ date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let stamp = stamp(for: date, calendar: calendar)
        AppDefaults.store.set(stamp, forKey: dayStampKey)
        AppDefaults.store.set(calendar.startOfDay(for: date).timeIntervalSince1970, forKey: dayKey)
    }

    /// Puts the simulated day back on the real today. Used at launch and when the mode is switched.
    public static func resetSimulatedDay(calendar: Calendar = .autoupdatingCurrent) {
        setSimulatedDay(Date(), calendar: calendar)
    }

    /// Rewrites the stored instant after the device time zone changes, and keeps the chosen day.
    public static func rebaseSimulatedDayToCurrentTimeZone() {
        let zone = Calendar.autoupdatingCurrent
        guard let stamp = storedStamp(),
              let date = combining(stamp: stamp, time: Date(), calendar: zone)
        else { return }
        AppDefaults.store.set(zone.startOfDay(for: date).timeIntervalSince1970, forKey: dayKey)
    }

    private static func storedStamp() -> String? {
        if let stamp = AppDefaults.store.string(forKey: dayStampKey), !stamp.isEmpty {
            return stamp
        }
        let stored = AppDefaults.store.double(forKey: dayKey)
        guard stored > 0 else { return nil }
        return stamp(for: Date(timeIntervalSince1970: stored))
    }
}
