import Foundation
import LififyCore

/// The two kinds of system data Lifify reads and writes through EventKit.
public enum CalendarEntity: Sendable {
    case event
    case reminder
}

/// One calendar occurrence as read from the system calendar.
public struct CalendarEventSnapshot: Sendable {
    public var identifier: String
    public var title: String?
    public var notes: String?
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var recurrence: ReminderRecurrenceMetadata?
    public var hasRecurrenceRules: Bool

    /// Creates a snapshot of one occurrence.
    public init(
        identifier: String,
        title: String?,
        notes: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrence: ReminderRecurrenceMetadata? = nil,
        hasRecurrenceRules: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.hasRecurrenceRules = hasRecurrenceRules
    }
}

/// One open reminder as read from the system Reminders app.
public struct CalendarReminderSnapshot: Sendable {
    public var identifier: String
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var recurrence: ReminderRecurrenceMetadata?

    /// Creates a snapshot of one open reminder.
    public init(
        identifier: String,
        title: String,
        notes: String,
        dueDate: Date?,
        recurrence: ReminderRecurrenceMetadata? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.recurrence = recurrence
    }
}

/// The values needed to create or update one calendar event.
public struct CalendarEventDraft: Sendable, Equatable {
    public var externalIdentifier: String?
    public var originalStart: Date?
    public var title: String
    public var notes: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var occurrenceOnly: Bool

    /// Creates a draft for one calendar write.
    public init(
        externalIdentifier: String?,
        originalStart: Date?,
        title: String,
        notes: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        occurrenceOnly: Bool = false
    ) {
        self.externalIdentifier = externalIdentifier
        self.originalStart = originalStart
        self.title = title
        self.notes = notes
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.occurrenceOnly = occurrenceOnly
    }
}

/// The values needed to create or update one reminder.
public struct CalendarReminderDraft: Sendable, Equatable {
    /// The system identifier without Lifify's `reminder:` prefix.
    public var identifier: String?
    public var title: String
    public var notes: String
    public var startDate: Date
    public var endDate: Date?
    public var recurrence: ChallengeRecurrence
    public var interval: Int
    public var weekdays: Set<Int>
    public var includesTime: Bool

    /// Creates a draft for one reminder write.
    public init(
        identifier: String?,
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date?,
        recurrence: ChallengeRecurrence,
        interval: Int,
        weekdays: Set<Int>,
        includesTime: Bool
    ) {
        self.identifier = identifier
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.recurrence = recurrence
        self.interval = interval
        self.weekdays = weekdays
        self.includesTime = includesTime
    }
}

/// Every access Lifify makes to the system calendar and Reminders.
///
/// The app uses ``EventKitCalendarGateway``. Tests install a recording stand-in, so they
/// can cover paths that delete real calendar data without touching a real calendar.
@MainActor
public protocol CalendarGateway: AnyObject {
    /// Says whether Lifify may use the entity, optionally asking the user first.
    func hasAccess(to entity: CalendarEntity, prompt: Bool) async throws -> Bool
    /// Returns the occurrences inside the window.
    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot]
    /// Returns all open reminders.
    func openReminders() async -> [CalendarReminderSnapshot]
    /// Creates or updates an event and returns its system identifier, or `nil` on failure.
    func saveEvent(_ draft: CalendarEventDraft) async -> String?
    /// Removes a single occurrence. Failures are ignored because local data stays authoritative.
    func deleteEvent(identifier: String, occurrenceStart: Date) async
    /// Reads the recurrence of an occurrence, or `nil` when none can be read.
    func recurrence(identifier: String, occurrenceStart: Date) async -> ReminderRecurrenceMetadata?
    /// Sets a reminder's completion state. Failures are ignored.
    func setReminderCompleted(identifier: String, isCompleted: Bool) async
    /// Creates or updates a reminder and returns its system identifier, or `nil` on failure.
    func saveReminder(_ draft: CalendarReminderDraft) async -> String?
    /// Returns the Reminders lists that can take new reminders.
    func reminderLists() async -> [ReminderListOption]
}

/// Holds the gateway that all calendar code goes through.
@MainActor
public enum CalendarBridge {
    /// The active gateway. It is the real EventKit one unless a test replaced it.
    public private(set) static var current: any CalendarGateway = EventKitCalendarGateway()

    /// Installs a gateway, or restores the real one when passed `nil`.
    public static func use(_ gateway: (any CalendarGateway)?) {
        current = gateway ?? EventKitCalendarGateway()
    }
}
