import SwiftUI

struct ExerciseSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (WorkoutExerciseInfo) -> Void
    @AppStorage(WorkoutAPIKey.storageKey) private var apiKey = ""
    @State private var query = ""
    @State private var exercises: [WorkoutExerciseInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var manualName = ""

    var body: some View {
        NavigationStack {
            Group {
                if apiKeyMissing {
                    manualEntry(
                        title: L("API-Schlüssel fehlt", "API key missing"),
                        systemImage: "key",
                        message: L(
                            "Hinterlege den Schlüssel in den Einstellungen, damit Übungen und Bilder geladen werden. Ohne Schlüssel legst du die Übung mit einem Namen an.",
                            "Add the key in Settings so exercises and images can load. Without a key, create the exercise with a name."
                        )
                    )
                } else {
                    List(exercises) { exercise in
                        HStack(spacing: 12) {
                            ExerciseArtwork(code: exercise.code, side: 72)
                            Button {
                                onPick(exercise)
                                dismiss()
                            } label: {
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .overlay {
                        if isLoading && exercises.isEmpty {
                            ProgressView()
                        } else if let errorMessage, exercises.isEmpty {
                            manualEntry(
                                title: L("Übungen nicht geladen", "Exercises not loaded"),
                                systemImage: "wifi.exclamationmark",
                                message: errorMessage
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

    private var apiKeyMissing: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func manualEntry(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            VStack(alignment: .leading, spacing: 8) {
                TextField(L("Name der Übung", "Exercise name"), text: $manualName)
                    .textFieldStyle(.roundedBorder)
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
                .buttonStyle(.borderedProminent)
                .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 24)
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
