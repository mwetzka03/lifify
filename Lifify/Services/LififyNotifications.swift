import Foundation
import UserNotifications

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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

    static var briefingHour: Int {
        let stored = UserDefaults.standard.object(forKey: briefingHourKey) as? Int
        return min(max(stored ?? 8, 0), 23)
    }

    static var briefingMinute: Int {
        let stored = UserDefaults.standard.object(forKey: briefingMinuteKey) as? Int
        return min(max(stored ?? 0, 0), 59)
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
