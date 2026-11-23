import Foundation
import LififyChallenges
import LififyCore

/// One exercise of the bundled catalog.
public struct CatalogExercise: Decodable, Identifiable, Hashable, Sendable {
    public var exerciseId: String
    public var name: String
    public var gifUrl: String
    public var targetMuscles: [String]
    public var bodyParts: [String]
    public var equipments: [String]

    public var id: String { exerciseId }

    public var muscleSummary: String {
        targetMuscles.joined(separator: ", ")
    }

    public init(exerciseId: String, name: String, gifUrl: String, targetMuscles: [String], bodyParts: [String], equipments: [String]) {
        self.exerciseId = exerciseId
        self.name = name
        self.gifUrl = gifUrl
        self.targetMuscles = targetMuscles
        self.bodyParts = bodyParts
        self.equipments = equipments
    }
}

/// Finds exercises in the bundled catalog.
public enum ExerciseCatalog {
    public static let exercises: [CatalogExercise] = load()

    /// Returns an exercise by ID.
    public static func exercise(id: String) -> CatalogExercise? {
        exercises.first { $0.exerciseId == id }
    }

    /// Returns the animation URL of an exercise.
    public static func gifURL(for code: String) -> URL? {
        guard let raw = exercise(id: code)?.gifUrl, let url = URL(string: raw) else { return nil }
        return url
    }

    /// Searches the catalog.
    public static func search(_ query: String) -> [CatalogExercise] {
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

    /// Converts a catalog exercise for a plan.
    public static func info(for exercise: CatalogExercise) -> WorkoutExerciseInfo {
        WorkoutExerciseInfo(
            id: exercise.exerciseId,
            code: exercise.exerciseId,
            name: exercise.name,
            detail: exercise.bodyParts.joined(separator: ", "),
            muscle: exercise.muscleSummary
        )
    }

    /// Loads the bundled catalog.
    private static func load() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogExercise].self, from: data) else {
            return []
        }
        return decoded.map { exercise in
            var named = exercise
            named.name = ExerciseName.formatted(exercise.name)
            return named
        }
    }
}

/// Formats exercise names.
public enum ExerciseName {
    /// Capitalizes each word.
    public static func formatted(_ name: String) -> String {
        name.split(separator: " ", omittingEmptySubsequences: true).map { word in
            word.split(separator: "-", omittingEmptySubsequences: false).map { part in
                guard let first = part.first else { return String(part) }
                return String(first).uppercased() + part.dropFirst().lowercased()
            }.joined(separator: "-")
        }.joined(separator: " ")
    }
}

/// Says where an exercise's media comes from.
public enum ExerciseMedia {
    /// Says whether the animation is loaded from the web.
    public static func isRemote(_ code: String) -> Bool {
        ExerciseCatalog.gifURL(for: code) != nil
    }
}
