import Combine
import Foundation
import LififyCore
import SwiftData

/// Imports system events and reminders and offers the calendar writes the app needs.
/// All system access goes through ``CalendarBridge``.
@MainActor
public final class EventKitSyncService: ObservableObject {
    /// Creates the service.
    public init() {}

    @Published public var isSyncing = false
    @Published public var message: String?
    private static var refreshInFlight = false
    private static let reminderPrefix = "reminder:"

    /// Imports events and reminders into the local store. Overlapping runs are skipped.
    ///
    /// - Parameters:
    ///   - context: The database context to write into.
    ///   - existingEvents: The local events to match against.
    ///   - existingChallenges: The local challenges linked to reminders.
    ///   - promptForAccess: Whether to ask for access and report the result to the user.
    public func sync(
        context: ModelContext,
        existingEvents: [ChallengeCalendarEvent],
        existingChallenges: [ChallengeItem],
        promptForAccess: Bool = true
    ) async {
        guard !Self.refreshInFlight else { return }
        Self.refreshInFlight = true
        isSyncing = true
        defer {
            isSyncing = false
            Self.refreshInFlight = false
        }
        do {
            let gateway = CalendarBridge.current
            let eventsAllowed = try await gateway.hasAccess(to: .event, prompt: promptForAccess)
            let remindersAllowed = try await gateway.hasAccess(to: .reminder, prompt: promptForAccess)
            let importedEvents = eventsAllowed
                ? importEvents(from: gateway, existing: existingEvents, context: context)
                : 0
            let importedReminders = remindersAllowed
                ? importReminders(
                    await gateway.openReminders(),
                    existingEvents: existingEvents,
                    existingChallenges: existingChallenges,
                    context: context
                )
                : 0
            try context.save()
            reconcileWorkoutLinks(context: context)
            if promptForAccess {
                message = String(
                    format: L("%d Termine und %d Erinnerungen synchronisiert.", "%d events and %d reminders synced."),
                    importedEvents,
                    importedReminders
                )
            }
        } catch {
            if promptForAccess { message = error.localizedDescription }
        }
    }

    /// Imports the sync window's occurrences and removes local copies that no longer exist.
    ///
    /// - Parameters:
    ///   - gateway: The calendar source.
    ///   - existing: The local events to match against.
    ///   - context: The database context to write into.
    /// - Returns: The number of imported occurrences.
    private func importEvents(
        from gateway: any CalendarGateway,
        existing: [ChallengeCalendarEvent],
        context: ModelContext
    ) -> Int {
        let now = Date()
        let snapshots = gateway.events(
            from: CalendarSyncWindow.start(around: now),
            to: CalendarSyncWindow.end(around: now)
        )
        var matchedIDs = Set<UUID>()
        for snapshot in snapshots {
            storeRecurrence(of: snapshot)
            let model = localEvent(for: snapshot, existing: existing, matchedIDs: matchedIDs, context: context)
            model.title = snapshot.title ?? model.title
            model.details = snapshot.notes ?? ""
            model.startDate = snapshot.startDate
            model.endDate = snapshot.endDate
            model.isAllDay = snapshot.isAllDay
            matchedIDs.insert(model.id)
        }
        for local in existing where CalendarSyncWindow.removesImportedEvent(
            start: local.startDate,
            externalIdentifier: local.externalIdentifier,
            matched: matchedIDs.contains(local.id),
            around: now
        ) {
            WorkoutLinkStore.removeEvent(local.id)
            context.delete(local)
        }
        return snapshots.count
    }

    /// Remembers or clears the recurrence of a system event.
    private func storeRecurrence(of snapshot: CalendarEventSnapshot) {
        if let metadata = snapshot.recurrence {
            EventRecurrenceStore.set(metadata, for: snapshot.identifier)
        } else if !snapshot.hasRecurrenceRules {
            EventRecurrenceStore.remove(for: snapshot.identifier)
        }
    }

    /// Finds the local copy of an occurrence, or creates one that inherits the series links.
    private func localEvent(
        for snapshot: CalendarEventSnapshot,
        existing: [ChallengeCalendarEvent],
        matchedIDs: Set<UUID>,
        context: ModelContext
    ) -> ChallengeCalendarEvent {
        if let matched = existing.first(where: {
            $0.externalIdentifier == snapshot.identifier &&
                !matchedIDs.contains($0.id) &&
                abs($0.startDate.timeIntervalSince(snapshot.startDate)) < 90
        }) {
            return matched
        }
        let sibling = existing.first { $0.externalIdentifier == snapshot.identifier }
        let inherited = CalendarSeriesLink.links(
            externalIdentifier: snapshot.identifier,
            events: existing.map {
                CalendarSeriesLink.Event(
                    externalIdentifier: $0.externalIdentifier,
                    challengeID: $0.linkedChallengeID,
                    groupID: $0.linkedChallengeGroupID,
                    rewardID: $0.linkedRewardID
                )
            }
        )
        let model = ChallengeCalendarEvent(
            title: snapshot.title ?? L("Kalenderereignis", "Calendar event"),
            startDate: snapshot.startDate,
            endDate: snapshot.endDate,
            isAllDay: snapshot.isAllDay,
            colorHex: sibling?.colorHex ?? "#4F7CAC",
            icon: sibling?.icon ?? "calendar",
            linkedChallengeID: inherited.challengeID,
            linkedChallengeGroupID: inherited.groupID,
            linkedRewardID: inherited.rewardID,
            externalIdentifier: snapshot.identifier,
            isReadOnly: true
        )
        context.insert(model)
        return model
    }

    /// Updates linked challenges and suggestion events from the open reminders.
    ///
    /// - Parameters:
    ///   - reminders: The open system reminders.
    ///   - existingEvents: The local events, including earlier suggestions.
    ///   - existingChallenges: The local challenges linked to reminders.
    ///   - context: The database context to write into.
    /// - Returns: The number of reminders imported as suggestions.
    private func importReminders(
        _ reminders: [CalendarReminderSnapshot],
        existingEvents: [ChallengeCalendarEvent],
        existingChallenges: [ChallengeItem],
        context: ModelContext
    ) -> Int {
        let activeIDs = Set(reminders.map { Self.reminderPrefix + $0.identifier })
        existingEvents
            .filter { $0.isReminderSuggestion && !activeIDs.contains($0.externalIdentifier ?? "") }
            .forEach(context.delete)
        var imported = 0
        for reminder in reminders where !reminder.identifier.isEmpty {
            let suggestionID = Self.reminderPrefix + reminder.identifier
            let previous = ReminderLinkStore.metadata(for: suggestionID)
            if let recurrence = reminder.recurrence {
                ReminderLinkStore.set(recurrence, for: suggestionID)
            } else if previous?.recurrence != .irregular {
                ReminderLinkStore.remove(for: suggestionID)
            }
            if let legacy = existingChallenges.first(where: {
                $0.externalIdentifier == reminder.identifier && $0.isReadOnly
            }) {
                context.delete(legacy)
            }
            if let linked = existingChallenges.first(where: { $0.externalIdentifier == suggestionID }) {
                applyRecurrence(of: reminder, previous: previous, to: linked)
                continue
            }
            upsertSuggestion(for: reminder, identifier: suggestionID, existing: existingEvents, context: context)
            imported += 1
        }
        return imported
    }

    /// Copies a reminder's recurrence onto its challenge. Irregular challenges keep theirs.
    private func applyRecurrence(
        of reminder: CalendarReminderSnapshot,
        previous: ReminderRecurrenceMetadata?,
        to challenge: ChallengeItem
    ) {
        if let recurrence = reminder.recurrence {
            challenge.recurrence = recurrence.recurrence
            challenge.weekdaySet = recurrence.weekdays
            challenge.endDate = recurrence.endDate
        } else if previous?.recurrence != .irregular {
            challenge.recurrence = .none
            challenge.weekdaySet = []
            challenge.endDate = nil
        }
    }

    /// Creates or refreshes the one-hour suggestion event of a reminder.
    private func upsertSuggestion(
        for reminder: CalendarReminderSnapshot,
        identifier: String,
        existing: [ChallengeCalendarEvent],
        context: ModelContext
    ) {
        let dueDate = reminder.dueDate ?? .now
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: dueDate) ?? dueDate
        let suggestion = existing.first { $0.externalIdentifier == identifier } ??
            ChallengeCalendarEvent(
                title: reminder.title,
                startDate: dueDate,
                endDate: end,
                icon: "lightbulb",
                externalIdentifier: identifier,
                isReadOnly: true
            )
        suggestion.title = reminder.title
        suggestion.details = reminder.notes
        suggestion.startDate = dueDate
        suggestion.endDate = end
        if suggestion.modelContext == nil { context.insert(suggestion) }
    }

    /// Aligns the workout links with the stored calendar events.
    private func reconcileWorkoutLinks(context: ModelContext) {
        let stored = (try? context.fetch(FetchDescriptor<ChallengeCalendarEvent>())) ?? []
        WorkoutLinkStore.reconcile(calendar: stored.filter { !$0.isReminderSuggestion }.map {
            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
        })
    }

    /// Creates or updates a system calendar event.
    ///
    /// - Parameters:
    ///   - externalIdentifier: The system event to update, or `nil` to create one.
    ///   - originalStart: The start of the occurrence being changed.
    ///   - title: The event title.
    ///   - notes: The event notes.
    ///   - start: The new start.
    ///   - end: The new end.
    ///   - isAllDay: Whether the event lasts all day.
    ///   - occurrenceOnly: Whether later occurrences of a series stay unchanged.
    /// - Returns: The system identifier, or `nil` on failure.
    public static func saveCalendarEvent(
        externalIdentifier: String?,
        originalStart: Date?,
        title: String,
        notes: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        occurrenceOnly: Bool = false
    ) async -> String? {
        await CalendarBridge.current.saveEvent(CalendarEventDraft(
            externalIdentifier: externalIdentifier,
            originalStart: originalStart,
            title: title,
            notes: notes,
            start: start,
            end: end,
            isAllDay: isAllDay,
            occurrenceOnly: occurrenceOnly
        ))
    }

    /// Removes one occurrence from the system calendar.
    public static func deleteCalendarEvent(externalIdentifier: String, occurrenceStart: Date) async {
        await CalendarBridge.current.deleteEvent(identifier: externalIdentifier, occurrenceStart: occurrenceStart)
    }

    /// Loads an event's recurrence, falling back to the last stored value.
    public static func loadRecurrence(externalIdentifier: String, occurrenceStart: Date) async -> ReminderRecurrenceMetadata? {
        guard let metadata = await CalendarBridge.current.recurrence(
            identifier: externalIdentifier,
            occurrenceStart: occurrenceStart
        ) else {
            return EventRecurrenceStore.metadata(for: externalIdentifier)
        }
        EventRecurrenceStore.set(metadata, for: externalIdentifier)
        return metadata
    }

    /// Mirrors a challenge's completion onto its linked reminder.
    public static func setReminderCompletion(externalIdentifier: String, isCompleted: Bool) async {
        guard externalIdentifier.hasPrefix(reminderPrefix) else { return }
        let identifier = String(externalIdentifier.dropFirst(reminderPrefix.count))
        guard !identifier.isEmpty else { return }
        await CalendarBridge.current.setReminderCompleted(identifier: identifier, isCompleted: isCompleted)
    }

    /// Creates or updates a system reminder and remembers its recurrence.
    ///
    /// - Parameters:
    ///   - externalIdentifier: The linked identifier with `reminder:` prefix, if any.
    ///   - title: The reminder title.
    ///   - notes: The reminder notes.
    ///   - startDate: The due date.
    ///   - endDate: The end of the recurrence.
    ///   - recurrence: How the reminder repeats.
    ///   - recurrenceInterval: The repeat interval, at least 1.
    ///   - weekdays: The weekdays of a weekly recurrence.
    ///   - includesTime: Whether the due date carries a time.
    /// - Returns: The linked identifier with `reminder:` prefix, or `nil` on failure.
    public static func saveReminder(
        externalIdentifier: String?,
        title: String,
        notes: String,
        startDate: Date,
        endDate: Date?,
        recurrence: ChallengeRecurrence,
        recurrenceInterval: Int,
        weekdays: Set<Int>,
        includesTime: Bool = false
    ) async -> String? {
        let interval = max(recurrenceInterval, 1)
        let existing = externalIdentifier.flatMap {
            $0.hasPrefix(reminderPrefix) ? String($0.dropFirst(reminderPrefix.count)) : nil
        }
        guard let saved = await CalendarBridge.current.saveReminder(CalendarReminderDraft(
            identifier: existing,
            title: title,
            notes: notes,
            startDate: startDate,
            endDate: endDate,
            recurrence: recurrence,
            interval: interval,
            weekdays: weekdays,
            includesTime: includesTime
        )) else { return nil }
        let linked = reminderPrefix + saved
        if recurrence == .none {
            ReminderLinkStore.remove(for: linked)
        } else {
            ReminderLinkStore.set(
                ReminderRecurrenceMetadata(
                    recurrence: recurrence,
                    interval: interval,
                    weekdays: weekdays,
                    endDate: endDate
                ),
                for: linked
            )
        }
        return linked
    }
}
