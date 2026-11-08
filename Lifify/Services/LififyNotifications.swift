import Foundation
import UserNotifications

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Local pushes for abstinence bonuses and the daily briefing.
@MainActor
enum LififyNotifications {
    nonisolated static let briefingEnabledKey = "lifify.briefingEnabled"
    nonisolated static let briefingHourKey = "lifify.briefingHour"
    nonisolated static let briefingMinuteKey = "lifify.briefingMinute"
    private static let briefingPrefix = "lifify.briefing."

    static var briefingEnabled: Bool {
        if UserDefaults.standard.object(forKey: briefingEnabledKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: briefingEnabledKey)
    }

    nonisolated static var briefingHour: Int {
        let stored = UserDefaults.standard.object(forKey: briefingHourKey) as? Int
        return min(max(stored ?? 8, 0), 23)
    }

    nonisolated static var briefingMinute: Int {
        let stored = UserDefaults.standard.object(forKey: briefingMinuteKey) as? Int
        return min(max(stored ?? 0, 0), 59)
    }

    nonisolated static let briefingWeekKey = "lifify.briefingWeek"
    nonisolated static let briefingRevisionKey = "lifify.briefingRevision"

    nonisolated static func clock(for weekday: Int) -> BriefingClock {
        BriefingSchedule.clock(
            weekday: weekday,
            overrides: weekdayMap(),
            fallback: BriefingClock(hour: briefingHour, minute: briefingMinute)
        )
    }

    nonisolated static func setClock(weekday: Int, hour: Int, minute: Int) {
        var map = weekdayMap()
        map[weekday] = BriefingClock(hour: hour, minute: minute)
        saveWeekdayMap(map)
    }

    static func resetWeekdayClocks() {
        UserDefaults.standard.removeObject(forKey: briefingWeekKey)
        bumpBriefing()
    }

    static func exportWeekdayRecords() -> [BackupRecord] {
        weekdayMap().compactMap { weekday, clock in
            guard let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", weekday)) else { return nil }
            return BackupRecord(type: "briefingWeekday", id: id, integers: [weekday, clock.hour, clock.minute])
        }
    }

    static func restoreWeekday(_ record: BackupRecord) {
        guard record.integers.count >= 3 else { return }
        setClock(weekday: record.integers[0], hour: record.integers[1], minute: record.integers[2])
    }

    nonisolated private static func weekdayMap() -> [Int: BriefingClock] {
        guard let data = UserDefaults.standard.data(forKey: briefingWeekKey),
              let raw = try? JSONDecoder().decode([String: [Int]].self, from: data)
        else { return [:] }
        var map: [Int: BriefingClock] = [:]
        for (key, value) in raw {
            guard let weekday = Int(key), value.count >= 2 else { continue }
            map[weekday] = BriefingClock(hour: value[0], minute: value[1])
        }
        return map
    }

    nonisolated private static func saveWeekdayMap(_ map: [Int: BriefingClock]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { key, clock in
            (String(key), [clock.hour, clock.minute])
        })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: briefingWeekKey)
        }
        bumpBriefing()
    }

    nonisolated private static func bumpBriefing() {
        let revision = UserDefaults.standard.integer(forKey: briefingRevisionKey)
        UserDefaults.standard.set(revision + 1, forKey: briefingRevisionKey)
    }

    static func requestAccess() async -> Bool {
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

    static func announceBonus(id: String, title: String, body: String, due: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let queued = pending.contains { $0.identifier == id } || delivered.contains { $0.request.identifier == id }
        guard DailyBriefing.shouldDeliverBonusNow(due: due, realNow: Date(), alreadyQueued: queued) else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id])
        deliver(id: id, title: title, body: body, at: nil)
    }

    static func schedule(id: String, title: String, body: String, at date: Date) {
        guard date > Date() else { return }
        deliver(id: id, title: title, body: body, at: date)
    }

    static func replaceBriefings(_ items: [(id: String, title: String, body: String, date: Date)]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(briefingPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for item in items {
            schedule(id: item.id, title: item.title, body: item.body, at: item.date)
        }
    }

    static func cancel(idPrefix: String, keeping keep: Set<String> = []) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let matching = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) && !keep.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: matching)
    }

    static func cancelBriefings() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(briefingPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
    }

    private static func deliver(id: String, title: String, body: String, at date: Date?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger: UNNotificationTrigger?
        if let date {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        } else {
            trigger = nil
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
