import Foundation
import UserNotifications

/// How a local notification sits on the clock.
/// A wall-clock time follows the device time zone, like an Apple alarm.
/// An absolute time stays the same instant, like a timer.
public enum NotificationTiming {
    /// Builds the delivery time, fixed to a zone or following the device.
    public static func components(
        for date: Date,
        followsDeviceTimeZone: Bool,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DateComponents {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        parts.timeZone = followsDeviceTimeZone ? nil : calendar.timeZone
        return parts
    }
}

/// Shows notifications while the app is open.
public final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NotificationCenterDelegate()

    /// Presents a notification in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Passes the screen a tapped notification should open to the app.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let route = response.notification.request.content.userInfo[NotificationRoute.key] as? String else { return }
        await MainActor.run { NotificationRoute.open(route) }
    }
}

/// The screen a tapped notification opens, also when the tap launched the app.
@MainActor
public enum NotificationRoute {
    /// The notification's field that names the screen.
    public nonisolated static let key = "lifify.route"
    /// Posted when a route is waiting.
    public static let didChange = Notification.Name("lifify.notificationRoute")
    private static var pending: String?

    /// Remembers the route and tells the running app.
    public static func open(_ route: String) {
        pending = route
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Hands out the waiting route once.
    public static func take() -> String? {
        defer { pending = nil }
        return pending
    }
}

/// Local pushes for abstinence bonuses and the daily briefing.
@MainActor
public enum LififyNotifications {
    public nonisolated static let briefingEnabledKey = "lifify.briefingEnabled"
    public nonisolated static let briefingHourKey = "lifify.briefingHour"
    public nonisolated static let briefingMinuteKey = "lifify.briefingMinute"
    private static let briefingPrefix = "lifify.briefing."

    public static var briefingEnabled: Bool {
        if AppDefaults.store.object(forKey: briefingEnabledKey) == nil { return true }
        return AppDefaults.store.bool(forKey: briefingEnabledKey)
    }

    public nonisolated static var briefingHour: Int {
        let stored = AppDefaults.store.object(forKey: briefingHourKey) as? Int
        return min(max(stored ?? 8, 0), 23)
    }

    public nonisolated static var briefingMinute: Int {
        let stored = AppDefaults.store.object(forKey: briefingMinuteKey) as? Int
        return min(max(stored ?? 0, 0), 59)
    }

    public nonisolated static let briefingWeekKey = "lifify.briefingWeek"
    public nonisolated static let briefingRevisionKey = "lifify.briefingRevision"

    /// Returns the briefing time of a weekday.
    public nonisolated static func clock(for weekday: Int) -> BriefingClock {
        let stored = storedWeek()[weekday]
        let overrides = stored.map { [weekday: BriefingClock(hour: $0.hour, minute: $0.minute)] } ?? [:]
        return BriefingSchedule.clock(
            weekday: weekday,
            overrides: overrides,
            fallback: BriefingClock(hour: briefingHour, minute: briefingMinute)
        )
    }

    /// Says whether the briefing is on for a weekday.
    public nonisolated static func dayEnabled(_ weekday: Int) -> Bool {
        storedWeek()[weekday]?.enabled ?? true
    }

    /// Turns the briefing on or off for a weekday.
    public nonisolated static func setDayEnabled(_ weekday: Int, _ enabled: Bool) {
        var map = storedWeek()
        let clock = clock(for: weekday)
        let current = map[weekday]
        map[weekday] = StoredBriefingDay(
            hour: current?.hour ?? clock.hour,
            minute: current?.minute ?? clock.minute,
            enabled: enabled
        )
        saveWeek(map)
    }

    /// Sets the briefing time of a weekday.
    public nonisolated static func setClock(weekday: Int, hour: Int, minute: Int) {
        var map = storedWeek()
        let enabled = map[weekday]?.enabled ?? true
        map[weekday] = StoredBriefingDay(hour: hour, minute: minute, enabled: enabled)
        saveWeek(map)
    }

    /// Removes all per-weekday briefing settings.
    public static func resetWeekdayClocks() {
        AppDefaults.store.removeObject(forKey: briefingWeekKey)
        bumpBriefing()
    }

    /// Exports the weekday settings for a backup.
    public static func exportWeekdayRecords() -> [BackupRecord] {
        storedWeek().compactMap { weekday, day in
            guard let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", weekday)) else { return nil }
            return BackupRecord(
                type: "briefingWeekday",
                id: id,
                integers: [weekday, day.hour, day.minute, day.enabled ? 1 : 0]
            )
        }
    }

    /// Restores one weekday setting from a backup.
    public static func restoreWeekday(_ record: BackupRecord) {
        guard record.integers.count >= 3 else { return }
        setClock(weekday: record.integers[0], hour: record.integers[1], minute: record.integers[2])
        if record.integers.count >= 4 {
            setDayEnabled(record.integers[0], record.integers[3] != 0)
        }
    }

    /// Reads the stored week.
    nonisolated private static func storedWeek() -> [Int: StoredBriefingDay] {
        guard let data = AppDefaults.store.data(forKey: briefingWeekKey),
              let raw = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return [:] }
        var map: [Int: StoredBriefingDay] = [:]
        for (key, value) in raw {
            guard let weekday = Int(key), value.count >= 2 else { continue }
            map[weekday] = StoredBriefingDay(
                hour: value[0],
                minute: value[1],
                enabled: value.count >= 3 ? value[2] != 0 : true
            )
        }
        return map
    }

    /// Writes the stored week and signals the change.
    nonisolated private static func saveWeek(_ map: [Int: StoredBriefingDay]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { key, day in
            (String(key), [day.hour, day.minute, day.enabled ? 1 : 0])
        })
        if let data = try? JSONEncoder().encode(raw) {
            AppDefaults.store.set(data, forKey: briefingWeekKey)
        }
        bumpBriefing()
    }

    /// Signals that the briefing settings changed.
    nonisolated private static func bumpBriefing() {
        let revision = AppDefaults.store.integer(forKey: briefingRevisionKey)
        AppDefaults.store.set(revision + 1, forKey: briefingRevisionKey)
    }

    /// Asks for notification permission when it is still undecided.
    public static func requestAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Sends a bonus notification once, if it is due now.
    public static func announceBonus(id: String, title: String, body: String, due: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let queued = pending.contains { $0.identifier == id } || delivered.contains { $0.request.identifier == id }
        guard DailyBriefing.shouldDeliverBonusNow(due: due, realNow: Date(), alreadyQueued: queued) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        deliver(id: id, title: title, body: body, at: nil, followsDeviceTimeZone: false)
    }

    /// Schedules a notification. A time in the past is ignored.
    public static func schedule(
        id: String,
        title: String,
        body: String,
        at date: Date,
        followsDeviceTimeZone: Bool = false
    ) {
        guard date > Date() else { return }
        deliver(id: id, title: title, body: body, at: date, followsDeviceTimeZone: followsDeviceTimeZone)
    }

    /// Sends a notification now. A tap opens the given route.
    public static func send(id: String, title: String, body: String, route: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [NotificationRoute.key: route]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil), withCompletionHandler: nil)
    }

    /// Replaces all scheduled briefings.
    public static func replaceBriefings(_ items: [(id: String, title: String, body: String, date: Date)]) async {
        await replace(prefix: briefingPrefix, items: items, followsDeviceTimeZone: true)
    }

    /// Replaces all pending notifications with a prefix.
    ///
    /// - Parameters:
    ///   - prefix: The identifier prefix of the group.
    ///   - items: The new notifications.
    ///   - followsDeviceTimeZone: Whether times follow the device's time zone.
    public static func replace(
        prefix: String,
        items: [(id: String, title: String, body: String, date: Date)],
        followsDeviceTimeZone: Bool
    ) async {
        await cancel(idPrefix: prefix)
        for item in items {
            schedule(
                id: item.id,
                title: item.title,
                body: item.body,
                at: item.date,
                followsDeviceTimeZone: followsDeviceTimeZone
            )
        }
    }

    /// Cancels pending notifications with a prefix, except the kept ones.
    public static func cancel(idPrefix: String, keeping keep: Set<String> = []) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let matching = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: matching)
    }

    /// Cancels all pending briefings.
    public static func cancelBriefings() async {
        await cancel(idPrefix: briefingPrefix)
    }

    /// Hands a notification to the system. Without a date it is delivered at once.
    ///
    /// - Parameters:
    ///   - id: The notification identifier.
    ///   - title: The title.
    ///   - body: The text.
    ///   - date: The delivery time, or `nil` for now.
    ///   - followsDeviceTimeZone: Whether the time follows the device's time zone.
    private static func deliver(
        id: String,
        title: String,
        body: String,
        at date: Date?,
        followsDeviceTimeZone: Bool
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger: UNNotificationTrigger?
        if let date {
            let parts = NotificationTiming.components(for: date, followsDeviceTimeZone: followsDeviceTimeZone)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
