import SwiftData
import SwiftUI

/// Packs optional challenge estimates into one calendar slot.
/// Sport and abstinence are not offered here.
struct EventChallengeTimeSection: View {
    @Binding var memberIDs: [UUID]
    let slotMinutes: Int
    let challenges: [ChallengeItem]
    var allowsAdding: Bool = true
    @Query private var completions: [ChallengeCompletion]
    @State private var filter: ChallengeTimeFilter = .all

    private var timedChallenges: [ChallengeItem] {
        challenges.filter {
            !$0.isArchived
                && ChallengeTimeRules.allowsTime($0.category)
                && !ChallengeCheckoff.followsNutrition($0.externalIdentifier)
        }
    }

    private var linkedMinutes: [Int] {
        memberIDs.compactMap { ChallengeTimeStore.minutes(for: $0) }
    }

    private var remaining: Int {
        ChallengeTimeRules.remaining(slotMinutes: slotMinutes, linkedMinutes: linkedMinutes)
    }

    private var visible: [ChallengeItem] {
        let done = Set(completions.map(\.challengeID))
        let candidates = timedChallenges.map { challenge in
            (
                id: challenge.id,
                minutes: ChallengeTimeStore.minutes(for: challenge.id),
                createdAt: challenge.createdAt,
                offered: EventOffer.isEnabled(for: challenge.id) || memberIDs.contains(challenge.id),
                finished: !memberIDs.contains(challenge.id) && !ChallengeActivity.staysOnActiveList(
                    recurrence: challenge.recurrence,
                    hasCompletion: done.contains(challenge.id)
                )
            )
        }
        let allowed = Set(ChallengeTimeRules.offeredSuggestions(candidates: candidates, already: []))
        return timedChallenges
            .filter { challenge in
                if !allowsAdding { return memberIDs.contains(challenge.id) }
                return allowed.contains(challenge.id)
            }
            .filter { challenge in
                ChallengeTimeRules.matches(filter, minutes: ChallengeTimeStore.minutes(for: challenge.id))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Group {
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
            Text(L(
                "Der Termin behält seine Länge, bis du eine Challenge abhakst. Dann fragst du die echte Dauer, und der Kalender wird rückwirkend angepasst. Die Restzeit ist nur die Anzeige. Sport und Abstinenz bleiben außen vor.",
                "The event keeps its length until you check off a challenge. Then you enter the real duration, and the calendar is revised. The time left is only a display. Sport and abstinence stay out of this."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func challengeToggle(_ challenge: ChallengeItem) -> some View {
        let minutes = ChallengeTimeStore.minutes(for: challenge.id)
        let selected = memberIDs.contains(challenge.id)
        return Button {
            if selected {
                memberIDs.removeAll { $0 == challenge.id }
            } else if allowsAdding {
                add(challenge)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                    Text(minutes.map { "\($0) \(L("Min", "min"))" } ?? L("Ohne Zeit", "Without time"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.green : Color.secondary)
            }
        }
        .disabled(!selected && !allowsAdding)
    }

    private func add(_ challenge: ChallengeItem) {
        guard !memberIDs.contains(challenge.id) else { return }
        memberIDs.append(challenge.id)
    }
}
