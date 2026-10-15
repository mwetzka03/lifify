import Foundation

struct WorkoutExerciseInfo: Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var detail: String
    var muscle: String
}

struct WorkoutPlan: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var exercises: [WorkoutPlanExercise]
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, exercises: [WorkoutPlanExercise] = [], updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.updatedAt = updatedAt
    }
}

struct WorkoutPlanExercise: Codable, Identifiable, Hashable {
    var id: UUID
    var code: String
    var name: String
    var restSeconds: Int
    var sets: [WorkoutPlanSet]

    init(id: UUID = UUID(), code: String, name: String, restSeconds: Int = 90, sets: [WorkoutPlanSet] = []) {
        self.id = id
        self.code = code
        self.name = name
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

struct WorkoutPlanSet: Codable, Identifiable, Hashable {
    var id: UUID
    var weightKg: Double
    var reps: Int

    init(id: UUID = UUID(), weightKg: Double = 0, reps: Int = 8) {
        self.id = id
        self.weightKg = weightKg
        self.reps = reps
    }
}

struct WorkoutSession: Codable, Identifiable, Hashable {
    var id: UUID
    var planID: UUID
    var planName: String
    var startedAt: Date
    var finishedAt: Date
    var exercises: [WorkoutSessionExercise]

    init(plan: WorkoutPlan, now: Date = .now) {
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

    var performedExercises: [WorkoutSessionExercise] {
        exercises.compactMap { exercise in
            let completed = exercise.sets.filter(\.completed)
            guard !completed.isEmpty else { return nil }
            var copy = exercise
            copy.sets = completed
            return copy
        }
    }
}

struct WorkoutSessionExercise: Codable, Identifiable, Hashable {
    var id: UUID
    var code: String
    var name: String
    var restSeconds: Int
    var sets: [WorkoutSessionSet]

    init(id: UUID = UUID(), code: String, name: String, restSeconds: Int, sets: [WorkoutSessionSet]) {
        self.id = id
        self.code = code
        self.name = name
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

struct WorkoutSessionSet: Codable, Identifiable, Hashable {
    var id: UUID
    var weightKg: Double
    var reps: Int
    var completed: Bool
    var targetWeightKg: Double
    var targetReps: Int

    init(
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

struct MealEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var detail: String
    var date: Date

    init(id: UUID = UUID(), name: String, detail: String = "", date: Date = .now) {
        self.id = id
        self.name = name
        self.detail = detail
        self.date = date
    }
}

enum WorkoutFormat {
    static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    static func weight(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: rounded(value))) ?? "\(rounded(value))"
    }

    static func weight(from text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "kg", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        return rounded(value)
    }

    static func rest(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func previous(weight weightKg: Double, reps: Int) -> String {
        "\(weight(weightKg)) kg × \(reps)"
    }
}
