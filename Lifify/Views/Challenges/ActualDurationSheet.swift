import SwiftUI

struct PendingDuration: Identifiable {
    let id = UUID()
    let challenge: ChallengeItem
    let date: Date
    let suggested: Int
}

/// Asks how long the checked-off challenge really took. The event moves once every linked challenge is done.
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
                Section {
                    LabeledContent(L("Minuten", "Minutes")) {
                        TextField("30", text: $text)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Text(L(
                        "Die Minuten zählen mit. Der Termin wird ersetzt, sobald jede verknüpfte Challenge abgehakt ist.",
                        "These minutes count. The event is replaced once every linked challenge is checked off."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .appGlassRow()
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
