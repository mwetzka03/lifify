import SwiftUI

struct ExerciseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (WorkoutExerciseInfo) -> Void
    @State private var query = ""
    @State private var manualName = ""

    private var results: [CatalogExercise] {
        ExerciseCatalog.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L("Eigene Übung", "Custom exercise")) {
                    TextField(L("Name der Übung", "Exercise name"), text: $manualName)
                    Button(L("Übung anlegen", "Create exercise")) {
                        let name = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        onPick(WorkoutExerciseInfo(
                            id: UUID().uuidString,
                            code: "MANUAL-\(UUID().uuidString)",
                            name: name,
                            detail: "",
                            muscle: ""
                        ))
                        dismiss()
                    }
                    .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section(L("Datenbank", "Database")) {
                    if results.isEmpty {
                        Text(L("Keine Treffer", "No matches"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { exercise in
                        HStack(spacing: 12) {
                            ExerciseArtwork(code: exercise.exerciseId, name: exercise.name, side: 72)
                            Button {
                                onPick(ExerciseCatalog.info(for: exercise))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !exercise.muscleSummary.isEmpty {
                                        Text(exercise.muscleSummary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(L("Übung suchen", "Search exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L("Name, z. B. Bench Press", "Name, for example Bench Press"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Schließen", "Close")) { dismiss() }
                }
            }
        }
    }
}
