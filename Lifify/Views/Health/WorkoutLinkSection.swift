import SwiftData
import SwiftUI

struct WorkoutLinkSection: View {
    let planID: UUID
    @Query(sort: \ChallengeItem.title) private var challenges: [ChallengeItem]
    @Query(sort: \ChallengeCalendarEvent.startDate, order: .reverse) private var events: [ChallengeCalendarEvent]
    @AppStorage(WorkoutLinkStore.revisionKey) private var revision = 0
    @State private var showingChallenges = false
    @State private var showingEvents = false

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
                "Mehrere Trainings können dieselbe Challenge nutzen, zum Beispiel Push und Pull für Gym. Ist eines davon an dem Tag fertig, wird die Challenge abgehakt und nur dieser Kalendereintrag angepasst.",
                "Several workouts can share one challenge, for example Push and Pull for Gym. Finishing any of them that day checks off the challenge and updates only that calendar entry."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Button { showingChallenges = true } label: {
                linkRow(
                    title: L("Challenges", "Challenges"),
                    systemImage: "target",
                    value: challengeSummary
                )
            }
            .buttonStyle(.plain)
            Button { showingEvents = true } label: {
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
        .sheet(isPresented: $showingChallenges) {
            WorkoutChallengePicker(planID: planID, challenges: linkableChallenges)
        }
        .sheet(isPresented: $showingEvents) {
            WorkoutEventPicker(planID: planID, events: calendarEvents)
        }
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
    }
}

private struct WorkoutChallengePicker: View {
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let challenges: [ChallengeItem]
    @State private var selected: Set<UUID>

    init(planID: UUID, challenges: [ChallengeItem]) {
        self.planID = planID
        self.challenges = challenges
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
                        WorkoutLinkStore.setChallenges(selected, for: planID)
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
    let events: [ChallengeCalendarEvent]
    @State private var selected: Set<UUID>

    init(planID: UUID, events: [ChallengeCalendarEvent]) {
        self.planID = planID
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
                                Text("\(AppDate.numeric(event.startDate)) · \(AppDate.time(event.startDate))")
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
                        WorkoutLinkStore.setEvents(selected, for: planID)
                        dismiss()
                    }
                }
            }
        }
    }
}
