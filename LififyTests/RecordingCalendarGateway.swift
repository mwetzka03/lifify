import Foundation
import LififyChallenges
import LififyCore

/// A calendar stand-in that records every write, so tests never touch a real calendar.
///
/// By default it denies access like a device without permission. A test sets
/// `grantsAccess` to exercise the paths that write to the calendar.
@MainActor
final class RecordingCalendarGateway: CalendarGateway {
    /// One recorded occurrence removal.
    struct Deletion: Equatable {
        let identifier: String
        let occurrenceStart: Date
    }

    var grantsAccess = false
    var storedEvents: [CalendarEventSnapshot] = []
    var storedReminders: [CalendarReminderSnapshot] = []
    private(set) var savedEvents: [CalendarEventDraft] = []
    private(set) var deletions: [Deletion] = []
    private(set) var savedReminders: [CalendarReminderDraft] = []
    private(set) var reminderCompletions: [String: Bool] = [:]
    private var nextIdentifier = 0

    /// Answers with the configured access.
    func hasAccess(to entity: CalendarEntity, prompt: Bool) async throws -> Bool { grantsAccess }

    /// Returns the configured occurrences inside the window.
    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        storedEvents.filter { $0.startDate >= start && $0.startDate <= end }
    }

    /// Returns the configured reminders.
    func openReminders() async -> [CalendarReminderSnapshot] { storedReminders }

    /// Records the write and returns the event's identifier, or a new one.
    func saveEvent(_ draft: CalendarEventDraft) async -> String? {
        guard grantsAccess else { return nil }
        savedEvents.append(draft)
        return draft.externalIdentifier ?? makeIdentifier()
    }

    /// Records the removal.
    func deleteEvent(identifier: String, occurrenceStart: Date) async {
        guard grantsAccess else { return }
        deletions.append(Deletion(identifier: identifier, occurrenceStart: occurrenceStart))
    }

    /// Returns the recurrence of a configured event.
    func recurrence(identifier: String, occurrenceStart: Date) async -> ReminderRecurrenceMetadata? {
        storedEvents.first { $0.identifier == identifier }?.recurrence
    }

    /// Records the completion state.
    func setReminderCompleted(identifier: String, isCompleted: Bool) async {
        guard grantsAccess else { return }
        reminderCompletions[identifier] = isCompleted
    }

    /// Records the write and returns the reminder's identifier, or a new one.
    func saveReminder(_ draft: CalendarReminderDraft) async -> String? {
        guard grantsAccess else { return nil }
        savedReminders.append(draft)
        return draft.identifier ?? makeIdentifier()
    }

    /// Creates a unique system identifier.
    private func makeIdentifier() -> String {
        nextIdentifier += 1
        return "system-\(nextIdentifier)"
    }
}
