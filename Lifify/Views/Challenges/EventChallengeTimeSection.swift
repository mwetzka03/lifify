import SwiftUI

/// Packs optional challenge estimates into one calendar slot.
/// Sport and abstinence are not offered here.
struct EventChallengeTimeSection: View {
    @Binding var memberIDs: [UUID]
    let slotMinutes: Int
    let challenges: [ChallengeItem]
    @State private var filter: ChallengeTimeFilter = .all

    private var timedChallenges: [ChallengeItem] {
        challenges.filter { !$0.isArchived && ChallengeTimeRules.allowsTime($0.category) }
    }

    private var linkedMinutes: [Int] {
        memberIDs.compactMap { ChallengeTimeStore.minutes(for: $0) }
    }

    private var remaining: Int {
        ChallengeTimeRules.remaining(slotMinutes: slotMinutes, linkedMinutes: linkedMinutes)
    }

    private var visible: [ChallengeItem] {
        timedChallenges.filter { challenge in
            ChallengeTimeRules.matches(filter, minutes: ChallengeTimeStore.minutes(for: challenge.id))
        }
    }

    private var suggestions: [ChallengeItem] {
        let ids = ChallengeTimeRules.suggestions(
            candidates: timedChallenges.map {
                (id: $0.id, minutes: ChallengeTimeStore.minutes(for: $0.id), createdAt: $0.createdAt)
            },
            now: AppClock.now,
            remaining: remaining,
            already: Set(memberIDs)
        )
        return ids.compactMap { id in timedChallenges.first { $0.id == id } }
    }

    var body: some View {
        Section {
            Picker(L("Filter", "Filter"), selection: $filter) {
                ForEach(ChallengeTimeFilter.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent(L("Noch frei", "Still free"), value: "\(remaining) \(L("Min", "min"))")
            if visible.isEmpty {
                Text(L("Keine passende Challenge.", "No matching challenge."))
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { challenge in
                challengeToggle(challenge)
            }
        } header: {
            Text(L("Challenges in diesem Slot", "Challenges in this slot"))
        } footer: {
            Text(L(
                "Der Slot ist die Obergrenze. Eine einzelne Challenge setzt den Termin auf ihre Dauer. Sind mehrere verknüpft und du erledigst nur einen Teil, schrumpft der Termin auf die erledigten Minuten. Sport und Abstinenz bleiben außen vor.",
                "The slot is the limit. A single challenge sets the event to its duration. When several are linked and you finish only some, the event shrinks to the finished minutes. Sport and abstinence stay out of this."
            ))
        }
        .appGlassRow()
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { challenge in
                    Button {
                        add(challenge)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title)
                            Text(L("Schon länger offen. Zum Slot hinzufügen?", "Open for a while. Add it to this slot?"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L("Vorschläge", "Suggestions"))
            }
            .appGlassRow()
        }
    }

    private func challengeToggle(_ challenge: ChallengeItem) -> some View {
        let minutes = ChallengeTimeStore.minutes(for: challenge.id)
        let selected = memberIDs.contains(challenge.id)
        let allowed = selected || ChallengeTimeRules.canAdd(minutes: minutes, remaining: remaining)
        return Button {
            if selected {
                memberIDs.removeAll { $0 == challenge.id }
            } else if allowed {
                add(challenge)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .foregroundStyle(allowed ? Color.primary : Color.secondary)
                    Text(minutes.map { "\($0) \(L("Min", "min"))" } ?? L("Ohne Zeit", "Without time"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.green : Color.secondary)
            }
        }
        .disabled(!allowed)
    }

    private func add(_ challenge: ChallengeItem) {
        guard !memberIDs.contains(challenge.id) else { return }
        guard ChallengeTimeRules.canAdd(minutes: ChallengeTimeStore.minutes(for: challenge.id), remaining: remaining) else { return }
        memberIDs.append(challenge.id)
    }
}
