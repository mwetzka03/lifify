import Foundation

/// An exercise from the catalog.
public struct WorkoutExerciseInfo: Identifiable, Hashable {
    public var id: String
    public var code: String
    public var name: String
    public var detail: String
    public var muscle: String

    public init(id: String, code: String, name: String, detail: String, muscle: String) {
        self.id = id
        self.code = code
        self.name = name
        self.detail = detail
        self.muscle = muscle
    }
}

/// A training plan.
public struct WorkoutPlan: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var exercises: [WorkoutPlanExercise]
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, exercises: [WorkoutPlanExercise] = [], updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.updatedAt = updatedAt
    }
}

/// An exercise inside a plan.
public struct WorkoutPlanExercise: Codable, Identifiable, Hashable {
    public var id: UUID
    public var code: String
    public var name: String
    public var restSeconds: Int
    public var sets: [WorkoutPlanSet]

    public init(id: UUID = UUID(), code: String, name: String, restSeconds: Int = 90, sets: [WorkoutPlanSet] = []) {
        self.id = id
        self.code = code
        self.name = name
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

/// A planned set.
public struct WorkoutPlanSet: Codable, Identifiable, Hashable {
    public var id: UUID
    public var weightKg: Double
    public var reps: Int

    public init(id: UUID = UUID(), weightKg: Double = 0, reps: Int = 8) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// One performed training session.
public struct WorkoutSession: Codable, Identifiable, Hashable {
    public var id: UUID
    public var planID: UUID
    public var planName: String
    public var startedAt: Date
    public var finishedAt: Date
    public var exercises: [WorkoutSessionExercise]

    /// Starts a session from a plan, with all sets not yet completed.
    public init(plan: WorkoutPlan, now: Date = .now) {
        id = UUID()
        planID = plan.id
        planName = plan.name
        startedAt = now
        finishedAt = now
        exercises = plan.exercises.map { exercise in
            WorkoutSessionExercise(
                code: exercise.code,
                name: exercise.name,
                restSeconds: exercise.restSeconds,
                sets: exercise.sets.map { set in
                    WorkoutSessionSet(
                        weightKg: set.weightKg,
                        reps: set.reps,
                        targetWeightKg: set.weightKg,
                        targetReps: set.reps
                    )
                }
            )
        }
    }

    public var durationSeconds: Int {
        max(0, Int(finishedAt.timeIntervalSince(startedAt).rounded(.down)))
    }

    public var performedExercises: [WorkoutSessionExercise] {
        exercises.compactMap { exercise in
            let completed = exercise.sets.filter(\.completed)
            guard !completed.isEmpty else { return nil }
            var copy = exercise
            copy.sets = completed
            return copy
        }
    }
}

/// An exercise inside a session.
public struct WorkoutSessionExercise: Codable, Identifiable, Hashable {
    public var id: UUID
    public var code: String
    public var name: String
    public var restSeconds: Int
    public var sets: [WorkoutSessionSet]

    public init(id: UUID = UUID(), code: String, name: String, restSeconds: Int, sets: [WorkoutSessionSet]) {
        self.id = id
        self.code = code
        self.name = name
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

/// A performed set.
public struct WorkoutSessionSet: Codable, Identifiable, Hashable {
    public var id: UUID
    public var weightKg: Double
    public var reps: Int
    public var completed: Bool
    public var targetWeightKg: Double
    public var targetReps: Int

    public init(
        id: UUID = UUID(),
        weightKg: Double,
        reps: Int,
        completed: Bool = false,
        targetWeightKg: Double,
        targetReps: Int
    ) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
        self.completed = completed
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
    }
}

/// A simple meal entry stored in the training file.
public struct MealEntry: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var detail: String
    public var date: Date

    public init(id: UUID = UUID(), name: String, detail: String = "", date: Date = .now) {
        self.id = id
        self.name = name
        self.detail = detail
        self.date = date
    }
}

/// Formats and parses training values.
public enum WorkoutFormat {
    /// Rounds to one decimal.
    public static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Formats a weight the German way.
    public static func weight(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: rounded(value))) ?? "\(rounded(value))"
    }

    /// Parses a typed weight.
    public static func weight(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "kg", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        return rounded(value)
    }

    /// Formats a rest time as minutes and seconds.
    public static func rest(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// Formats a duration.
    public static func duration(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// Formats the previous weight and repetitions.
    public static func previous(weight weightKg: Double, reps: Int) -> String {
        "\(weight(weightKg)) kg × \(reps)"
    }
}
