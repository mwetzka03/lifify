import SwiftData
import SwiftUI

struct WorkoutLinkSection: View {
    let planID: UUID
    @Query(sort: \ChallengeItem.title) private var challenges: [ChallengeItem]
    @Query(sort: \ChallengeCalendarEvent.startDate, order: .reverse) private var events: [ChallengeCalendarEvent]
    @AppStorage(WorkoutLinkStore.revisionKey) private var revision = 0
    @State private var picker: LinkPicker?

    private var linkableChallenges: [ChallengeItem] {
        challenges.filter { !$0.isArchived }
    }

    private var calendarEvents: [ChallengeCalendarEvent] {
        events.filter { !$0.isReminderSuggestion }
    }

    var body: some View {
        let _ = revision
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Verknüpfungen", "Links"))
                .font(.headline)
            Text(L(
                "Mehrere Trainings können dieselbe Challenge nutzen, ohne festem Wochentag. Ist an einem Tag eines davon fertig, wird die Challenge für diesen Tag abgehakt und nur der Kalendereintrag dieses Tages angepasst. Ohne eines dieser Trainings fällt der Eintrag nach dem Tag weg.",
                "Several workouts can share one challenge, with no fixed weekday. Finishing any of them checks off the challenge for that day and updates only that day’s calendar entry. If none of those workouts happened, that entry is removed after the day."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Button { picker = .challenges } label: {
                linkRow(
                    title: L("Challenges", "Challenges"),
                    systemImage: "target",
                    value: challengeSummary
                )
            }
            .buttonStyle(.plain)
            Button { picker = .events } label: {
                linkRow(
                    title: L("Kalender", "Calendar"),
                    systemImage: "calendar",
                    value: eventSummary
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.card, in: RoundedRectangle(cornerRadius: 16))
        .sheet(item: $picker) { kind in
            switch kind {
            case .challenges:
                WorkoutChallengePicker(planID: planID, challenges: linkableChallenges, events: calendarEvents)
            case .events:
                WorkoutEventPicker(planID: planID, challenges: linkableChallenges, events: calendarEvents)
            }
        }
        .onAppear { closeWorkoutLinks() }
        .onChange(of: calendarSignature) { closeWorkoutLinks() }
    }

    private var calendarSignature: String {
        calendarEvents.map { "\($0.id.uuidString):\($0.linkedChallengeID?.uuidString ?? "-")" }.joined(separator: "|")
    }

    private func closeWorkoutLinks() {
        WorkoutLinkStore.reconcile(calendar: calendarEvents.map {
            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
        })
    }

    private var challengeSummary: String {
        let ids = Set(WorkoutLinkStore.challengeIDs(for: planID))
        let names = linkableChallenges.filter { ids.contains($0.id) }.map(\.title)
        return names.isEmpty ? L("Keine", "None") : names.joined(separator: ", ")
    }

    private var eventSummary: String {
        let ids = Set(WorkoutLinkStore.eventIDs(for: planID))
        let names = calendarEvents.filter { ids.contains($0.id) }.map(\.title)
        return names.isEmpty ? L("Keine", "None") : names.joined(separator: ", ")
    }

    private func linkRow(title: String, systemImage: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private enum LinkPicker: String, Identifiable {
    case challenges
    case events
    var id: String { rawValue }
}

private struct WorkoutChallengePicker: View {
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let challenges: [ChallengeItem]
    let events: [ChallengeCalendarEvent]
    @State private var selected: Set<UUID>

    init(planID: UUID, challenges: [ChallengeItem], events: [ChallengeCalendarEvent]) {
        self.planID = planID
        self.challenges = challenges
        self.events = events
        _selected = State(initialValue: Set(WorkoutLinkStore.challengeIDs(for: planID)))
    }

    var body: some View {
        NavigationStack {
            List {
                if challenges.isEmpty {
                    Text(L("Keine Challenge.", "No challenge."))
                        .foregroundStyle(.secondary)
                }
                ForEach(challenges) { challenge in
                    Button {
                        if selected.contains(challenge.id) {
                            selected.remove(challenge.id)
                        } else {
                            selected.insert(challenge.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(challenge.title)
                                    .foregroundStyle(.primary)
                                Text(challenge.category.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(challenge.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(L("Challenges", "Challenges"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) {
                        let calendar = events.map {
                            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
                        }
                        let previous = WorkoutLinkRules.Snapshot(
                            challenges: Set(WorkoutLinkStore.challengeIDs(for: planID)),
                            events: Set(WorkoutLinkStore.eventIDs(for: planID))
                        )
                        let next = WorkoutLinkRules.applyChallenges(selected, previous: previous, calendar: calendar)
                        WorkoutLinkStore.replace(challenges: next.challenges, events: next.events, for: planID)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WorkoutEventPicker: View {
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let challenges: [ChallengeItem]
    let events: [ChallengeCalendarEvent]
    @State private var selected: Set<UUID>

    init(planID: UUID, challenges: [ChallengeItem], events: [ChallengeCalendarEvent]) {
        self.planID = planID
        self.challenges = challenges
        self.events = events
        _selected = State(initialValue: Set(WorkoutLinkStore.eventIDs(for: planID)))
    }

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    Text(L("Keine Kalendereinträge.", "No calendar events."))
                        .foregroundStyle(.secondary)
                }
                ForEach(events) { event in
                    Button {
                        if selected.contains(event.id) {
                            selected.remove(event.id)
                        } else {
                            selected.insert(event.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .foregroundStyle(.primary)
                                Text(eventPickerSubtitle(event))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected.contains(event.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(L("Kalender", "Calendar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) {
                        let calendar = events.map {
                            WorkoutLinkRules.CalendarLink(eventID: $0.id, challengeID: $0.linkedChallengeID)
                        }
                        let previous = WorkoutLinkRules.Snapshot(
                            challenges: Set(WorkoutLinkStore.challengeIDs(for: planID)),
                            events: Set(WorkoutLinkStore.eventIDs(for: planID))
                        )
                        let next = WorkoutLinkRules.applyEvents(selected, previous: previous, calendar: calendar)
                        WorkoutLinkStore.replace(challenges: next.challenges, events: next.events, for: planID)
                        dismiss()
                    }
                }
            }
        }
    }

    private func eventPickerSubtitle(_ event: ChallengeCalendarEvent) -> String {
        let when = "\(AppDate.numeric(event.startDate)) · \(AppDate.time(event.startDate))"
        guard let challengeID = event.linkedChallengeID,
              let title = challenges.first(where: { $0.id == challengeID })?.title
        else {
            return when
        }
        return "\(when) · \(LinkCaption.challenge(title))"
    }
}
