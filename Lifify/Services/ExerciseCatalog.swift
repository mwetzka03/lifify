import Foundation

struct CatalogExercise: Decodable, Identifiable, Hashable {
    var exerciseId: String
    var name: String
    var gifUrl: String
    var targetMuscles: [String]
    var bodyParts: [String]
    var equipments: [String]

    var id: String { exerciseId }

    var muscleSummary: String {
        targetMuscles.joined(separator: ", ")
    }
}

enum ExerciseCatalog {
    static let exercises: [CatalogExercise] = load()

    static func exercise(id: String) -> CatalogExercise? {
        exercises.first { $0.exerciseId == id }
    }

    static func gifURL(for code: String) -> URL? {
        guard let raw = exercise(id: code)?.gifUrl, let url = URL(string: raw) else { return nil }
        return url
    }

    static func search(_ query: String) -> [CatalogExercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !trimmed.isEmpty else { return source }
        return source.filter { exercise in
            exercise.name.localizedStandardContains(trimmed)
                || exercise.muscleSummary.localizedStandardContains(trimmed)
                || exercise.bodyParts.joined(separator: " ").localizedStandardContains(trimmed)
                || exercise.equipments.joined(separator: " ").localizedStandardContains(trimmed)
        }
    }

    static func info(for exercise: CatalogExercise) -> WorkoutExerciseInfo {
        WorkoutExerciseInfo(
            id: exercise.exerciseId,
            code: exercise.exerciseId,
            name: exercise.name,
            detail: exercise.bodyParts.joined(separator: ", "),
            muscle: exercise.muscleSummary
        )
    }

    private static func load() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogExercise].self, from: data) else {
            return []
        }
        return decoded
    }
}

enum ExerciseMedia {
    static func isRemote(_ code: String) -> Bool {
        ExerciseCatalog.gifURL(for: code) != nil
    }
}
