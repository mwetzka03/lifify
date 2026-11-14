import SwiftUI

struct PendingDuration: Identifiable {
    let id = UUID()
    let challenge: ChallengeItem
    let date: Date
    let suggested: Int
}

/// Asks how long the checked-off challenge really took, then the event is revised.
struct ActualDurationSheet: View {
    let suggested: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void
    @State private var text: String

    init(suggested: Int, onSave: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.suggested = suggested
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: String(max(suggested, 1)))
    }

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(L("Minuten", "Minutes")) {
                    TextField("30", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Text(L(
                    "Der Termin behält seinen Slot, bis du ihn abhakst. Die Minuten hier schreiben die Dauer im Kalender rückwirkend um.",
                    "The event keeps its slot until you check it off. These minutes revise the duration in the calendar."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .appGlassList()
            .navigationTitle(L("Echte Dauer", "Actual duration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern", "Save")) {
                        let minutes = Int(text.trimmingCharacters(in: .whitespaces)) ?? suggested
                        onSave(max(minutes, 1))
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
