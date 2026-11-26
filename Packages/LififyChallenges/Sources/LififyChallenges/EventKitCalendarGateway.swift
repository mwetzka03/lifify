@preconcurrency import EventKit
import Foundation
import LififyCore

/// The real calendar access. Each call opens a fresh store so it sees current system data.
@MainActor
public final class EventKitCalendarGateway: CalendarGateway {
    /// Creates the gateway.
    public init() {}

    /// Says whether full access exists, optionally asking the user first.
    public func hasAccess(to entity: CalendarEntity, prompt: Bool) async throws -> Bool {
        let type: EKEntityType = entity == .event ? .event : .reminder
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess || status == .authorized { return true }
        guard prompt else { return false }
        let store = EKEventStore()
        switch entity {
        case .event: return try await store.requestFullAccessToEvents()
        case .reminder: return try await store.requestFullAccessToReminders()
        }
    }

    /// Reads all identifiable occurrences inside the window.
    public func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).compactMap(Self.snapshot)
    }

    /// Reads all reminders that are not completed.
    public func openReminders() async -> [CalendarReminderSnapshot] {
        await Self.fetchOpenReminders()
    }

    /// Creates or updates an event. A recurring event changes from this occurrence on,
    /// unless the draft asks for this occurrence only.
    ///
    /// - Parameter draft: The event values and the occurrence they replace.
    /// - Returns: The system identifier, or `nil` without access, calendar, or on a failed save.
    public func saveEvent(_ draft: CalendarEventDraft) async -> String? {
        do {
            let store = EKEventStore()
            guard try await store.requestFullAccessToEvents() else { return nil }
            let event = Self.existingEvent(
                in: store,
                identifier: draft.externalIdentifier,
                originalStart: draft.originalStart
            ) ?? EKEvent(eventStore: store)
            if event.calendar == nil {
                let sibling = draft.calendarOfEvent.flatMap { store.event(withIdentifier: $0) }
                event.calendar = sibling?.calendar ?? store.defaultCalendarForNewEvents
            }
            guard event.calendar != nil else { return nil }
            Self.apply(draft, to: event)
            let span: EKSpan = draft.occurrenceOnly || !event.hasRecurrenceRules ? .thisEvent : .futureEvents
            try store.save(event, span: span, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Removes one occurrence. The local event is still removed when access is unavailable.
    public func deleteEvent(identifier: String, occurrenceStart: Date) async {
        do {
            let store = EKEventStore()
            guard try await store.requestFullAccessToEvents(),
                  let event = Self.existingEvent(in: store, identifier: identifier, originalStart: occurrenceStart)
            else { return }
            try store.remove(event, span: .thisEvent, commit: true)
        } catch {
            // Local data stays authoritative when Calendar cannot be updated.
        }
    }

    /// Reads the recurrence of the occurrence from the system calendar.
    public func recurrence(identifier: String, occurrenceStart: Date) async -> ReminderRecurrenceMetadata? {
        do {
            let store = EKEventStore()
            guard try await store.requestFullAccessToEvents(),
                  let event = Self.existingEvent(in: store, identifier: identifier, originalStart: occurrenceStart),
                  let rule = event.recurrenceRules?.first
            else { return nil }
            return Self.metadata(from: rule, referenceDate: event.startDate, calendar: .current)
        } catch {
            return nil
        }
    }

    /// Sets a reminder's completion state and date.
    public func setReminderCompleted(identifier: String, isCompleted: Bool) async {
        do {
            let store = EKEventStore()
            guard try await store.requestFullAccessToReminders(),
                  let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder
            else { return }
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? .now : nil
            try store.save(reminder, commit: true)
        } catch {
            // Local completion remains authoritative when EventKit cannot be updated.
        }
    }

    /// Creates or updates a reminder with its due date and recurrence.
    ///
    /// - Parameter draft: The reminder values.
    /// - Returns: The system identifier, or `nil` without access, list, or on a failed save.
    public func saveReminder(_ draft: CalendarReminderDraft) async -> String? {
        do {
            let store = EKEventStore()
            guard try await store.requestFullAccessToReminders() else { return nil }
            let reminder = draft.identifier.flatMap {
                store.calendarItem(withIdentifier: $0) as? EKReminder
            } ?? EKReminder(eventStore: store)
            if reminder.calendar == nil { reminder.calendar = Self.newReminderList(in: store) }
            guard reminder.calendar != nil else { return nil }
            reminder.title = draft.title
            reminder.notes = draft.notes
            reminder.dueDateComponents = Self.dueComponents(for: draft)
            reminder.recurrenceRules = Self.recurrenceRules(for: draft)
            try store.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            return nil
        }
    }

    /// Returns the Reminders lists that can take new reminders.
    public func reminderLists() async -> [ReminderListOption] {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else { return [] }
        return Self.writableLists(in: store).map { ReminderListOption(id: $0.calendarIdentifier, title: $0.title) }
    }

    /// The lists a new reminder can go into.
    private static func writableLists(in store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    /// The chosen list, else a To-Do list, else the system default.
    private static func newReminderList(in store: EKEventStore) -> EKCalendar? {
        let lists = writableLists(in: store)
        let options = lists.map { ReminderListOption(id: $0.calendarIdentifier, title: $0.title) }
        if let id = ReminderListChoice.pick(from: options), let list = lists.first(where: { $0.calendarIdentifier == id }) {
            return list
        }
        return store.defaultCalendarForNewReminders()
    }

    /// Copies the draft's values onto an event. An end before the start falls back to a default length.
    private static func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end > draft.start
            ? draft.end
            : draft.start.addingTimeInterval(draft.isAllDay ? 86_400 : 3_600)
    }

    /// Finds the exact occurrence near its original start, or else the event by identifier.
    private static func existingEvent(
        in store: EKEventStore,
        identifier: String?,
        originalStart: Date?
    ) -> EKEvent? {
        guard let identifier else { return nil }
        if let originalStart {
            let start = originalStart.addingTimeInterval(-36 * 3_600)
            let end = originalStart.addingTimeInterval(36 * 3_600)
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            if let occurrence = store.events(matching: predicate).first(where: {
                $0.eventIdentifier == identifier && abs($0.startDate.timeIntervalSince(originalStart)) < 90
            }) {
                return occurrence
            }
        }
        return store.event(withIdentifier: identifier)
    }

    /// Converts an event, skipping one without an identifier.
    private static func snapshot(_ event: EKEvent) -> CalendarEventSnapshot? {
        guard let identifier = event.eventIdentifier else { return nil }
        return CalendarEventSnapshot(
            identifier: identifier,
            title: event.title,
            notes: event.notes,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            recurrence: event.recurrenceRules?.first.flatMap {
                metadata(from: $0, referenceDate: event.startDate, calendar: .current)
            },
            hasRecurrenceRules: event.hasRecurrenceRules
        )
    }

    /// Translates an EventKit rule. A weekly rule without days uses the reference date's weekday.
    ///
    /// - Parameters:
    ///   - rule: The system recurrence rule.
    ///   - referenceDate: The occurrence date, if there is one.
    ///   - calendar: The calendar used to read the weekday.
    /// - Returns: Lifify's recurrence values, or `nil` for an unknown frequency.
    nonisolated private static func metadata(
        from rule: EKRecurrenceRule,
        referenceDate: Date?,
        calendar: Calendar
    ) -> ReminderRecurrenceMetadata? {
        let recurrence: ChallengeRecurrence
        switch rule.frequency {
        case .daily: recurrence = .daily
        case .weekly: recurrence = .weekly
        case .monthly: recurrence = .monthly
        case .yearly: recurrence = .yearly
        @unknown default: return nil
        }
        var weekdays = Set((rule.daysOfTheWeek ?? []).map { $0.dayOfTheWeek.rawValue })
        if recurrence == .weekly, weekdays.isEmpty, let referenceDate {
            weekdays.insert(calendar.component(.weekday, from: referenceDate))
        }
        return ReminderRecurrenceMetadata(
            recurrence: recurrence,
            interval: max(rule.interval, 1),
            weekdays: weekdays,
            endDate: rule.recurrenceEnd?.endDate
        )
    }

    /// Builds the due date, with a time only when the draft asks for one.
    private static func dueComponents(for draft: CalendarReminderDraft) -> DateComponents {
        let fields: Set<Calendar.Component> = draft.includesTime
            ? [.year, .month, .day, .hour, .minute]
            : [.year, .month, .day]
        var components = Calendar.current.dateComponents(fields, from: draft.startDate)
        components.calendar = Calendar.current
        return components
    }

    /// Builds the system recurrence rules for the draft.
    private static func recurrenceRules(for draft: CalendarReminderDraft) -> [EKRecurrenceRule] {
        let end = draft.endDate.map { EKRecurrenceEnd(end: $0) }
        let interval = max(draft.interval, 1)
        switch draft.recurrence {
        case .daily:
            return [EKRecurrenceRule(recurrenceWith: .daily, interval: interval, end: end)]
        case .weekly:
            return [weeklyRule(weekdays: draft.weekdays, interval: interval, end: end)]
        case .monthly:
            return [EKRecurrenceRule(recurrenceWith: .monthly, interval: interval, end: end)]
        case .yearly:
            return [EKRecurrenceRule(recurrenceWith: .yearly, interval: interval, end: end)]
        case .none, .irregular:
            return []
        }
    }

    /// Builds a weekly rule, ignoring weekday numbers outside 1...7.
    private static func weeklyRule(weekdays: Set<Int>, interval: Int, end: EKRecurrenceEnd?) -> EKRecurrenceRule {
        let days = weekdays
            .filter { (1...7).contains($0) }
            .compactMap { EKWeekday(rawValue: $0) }
            .map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(
            recurrenceWith: .weekly,
            interval: interval,
            daysOfTheWeek: days.isEmpty ? nil : days,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    /// Fetches open reminders off the main actor and converts them to sendable snapshots.
    nonisolated private static func fetchOpenReminders() async -> [CalendarReminderSnapshot] {
        let box = EventStoreBox()
        return await withCheckedContinuation { continuation in
            box.store.fetchReminders(matching: box.store.predicateForReminders(in: nil)) { reminders in
                continuation.resume(returning: (reminders ?? []).compactMap(reminderSnapshot))
            }
        }
    }

    /// Converts a reminder, skipping a completed one.
    nonisolated private static func reminderSnapshot(_ reminder: EKReminder) -> CalendarReminderSnapshot? {
        guard !reminder.isCompleted else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let dueDate = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
        return CalendarReminderSnapshot(
            identifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Erinnerung",
            notes: reminder.notes ?? "",
            dueDate: dueDate,
            recurrence: reminder.recurrenceRules?.first.flatMap {
                metadata(from: $0, referenceDate: dueDate, calendar: calendar)
            }
        )
    }
}

/// Carries a non-sendable event store into the reminder fetch callback.
private final class EventStoreBox: @unchecked Sendable {
    let store = EKEventStore()
}
