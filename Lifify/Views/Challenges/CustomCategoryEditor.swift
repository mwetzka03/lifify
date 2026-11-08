import SwiftUI

struct CustomCategoryEditor: View {
    let existing: CustomChallengeCategory?
    var onSave: (CustomChallengeCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var separate: Bool

    init(existing: CustomChallengeCategory?, onSave: @escaping (CustomChallengeCategory) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _separate = State(initialValue: existing?.separate ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Name", "Name"), text: $name)
                    Toggle(L("Separat anzeigen", "Show separately"), isOn: $separate)
                    Text(L(
                        "Separat heißt: die Kategorie bekommt eine eigene Überschrift in der Liste der aktiven Challenges. Sonst liegt sie bei den übrigen.",
                        "Separate means the category gets its own heading in the active challenge list. Otherwise it stays with the rest."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .appGlassRow()
            }
            .appGlassList()
            .navigationTitle(L("Kategorie", "Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let existing {
            ChallengeCategoryStore.update(id: existing.id, name: trimmedName, separate: separate)
            onSave(CustomChallengeCategory(id: existing.id, name: trimmedName, separate: separate))
        } else if let created = ChallengeCategoryStore.add(name: trimmedName, separate: separate) {
            onSave(created)
        }
        dismiss()
    }
}
