import SwiftUI

struct ExerciseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (WorkoutExerciseInfo) -> Void
    @AppStorage(WorkoutAPIKey.storageKey) private var apiKey = ""
    @State private var query = ""
    @State private var exercises: [WorkoutExerciseInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        L("API-Schlüssel fehlt", "API key missing"),
                        systemImage: "key",
                        description: Text(L(
                            "Hinterlege den Schlüssel aus deinem Workout-API-Konto, damit Übungen und Bilder geladen werden.",
                            "Add the key from your Workout API account so exercises and images can load."
                        ))
                    )
                } else {
                    List(exercises) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseArtwork(code: exercise.code, side: 72)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !exercise.muscle.isEmpty {
                                        Text(exercise.muscle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .overlay {
                        if isLoading && exercises.isEmpty {
                            ProgressView()
                        } else if let errorMessage, exercises.isEmpty {
                            ContentUnavailableView(
                                L("Übungen nicht geladen", "Exercises not loaded"),
                                systemImage: "wifi.exclamationmark",
                                description: Text(errorMessage)
                            )
                        } else if exercises.isEmpty {
                            ContentUnavailableView(L("Keine Treffer", "No matches"), systemImage: "magnifyingglass")
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
            .task(id: query) { await reload() }
        }
    }

    private func reload() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        let requested = query
        if !requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await WorkoutAPIClient.shared.exercises(matching: requested)
            guard !Task.isCancelled, requested == query else { return }
            exercises = loaded
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
