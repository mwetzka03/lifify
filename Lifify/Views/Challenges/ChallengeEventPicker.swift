import SwiftData
import SwiftUI

struct ChallengeEventPicker: View {
    @Binding var selection: UUID?
    let events: [ChallengeCalendarEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var visible: [ChallengeCalendarEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return events }
        return events.filter { $0.title.localizedStandardContains(trimmed) }
    }

    var body: some View {
        List {
            Button {
                selection = nil
                dismiss()
            } label: {
                HStack {
                    Text(L("Keiner", "None"))
                    Spacer()
                    if selection == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.green)
                    }
                }
            }
            .appGlassRow()
            ForEach(visible) { event in
                Button {
                    selection = event.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text(eventCaption(event))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selection == event.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Termin", "Event"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L("Termin suchen", "Search events"))
    }

    private func eventCaption(_ event: ChallengeCalendarEvent) -> String {
        let slot = ChallengeTimeStore.plannedMinutes(for: event.id)
            ?? ChallengeTimeRules.minutes(from: event.startDate, to: event.endDate)
        let linked = ChallengeTimeStore.memberIDs(for: event.id).compactMap { ChallengeTimeStore.minutes(for: $0) }
        return ChallengeTimeRules.scheduleCaption(
            allDay: event.isAllDay,
            dateText: AppDate.numeric(event.startDate),
            timeText: AppDate.time(event.startDate),
            slotMinutes: slot,
            linkedMinutes: linked
        )
    }
}
