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
            ForEach(visible) { event in
                Button {
                    selection = event.id
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text("\(AppDate.numeric(event.startDate)) · \(AppDate.time(event.startDate))")
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
        }
        .navigationTitle(L("Termin", "Event"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: L("Termin suchen", "Search events"))
    }
}
