import Foundation

enum WorkoutProgress {
    static func frequentWeight(weightsNewestFirst: [[Double]], limit: Int = 5) -> Double? {
        let sample = weightsNewestFirst.prefix(limit).flatMap { $0.map(WorkoutFormat.rounded) }
        guard !sample.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for weight in sample {
            counts[weight, default: 0] += 1
        }
        let best = counts.values.max() ?? 0
        let winners = Set(counts.filter { $0.value == best }.map(\.key))
        return sample.first { winners.contains($0) }
    }

    static func metPlan(_ sets: [WorkoutSessionSet]) -> Bool {
        guard !sets.isEmpty else { return false }
        return sets.allSatisfy { set in
            set.completed
                && WorkoutFormat.rounded(set.weightKg) + 0.001 >= WorkoutFormat.rounded(set.targetWeightKg)
                && set.reps >= set.targetReps
        }
    }

    static func sessionsNewestFirst(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.sorted { $0.finishedAt > $1.finishedAt }
    }

    static func previousPerformance(
        sessions: [WorkoutSession],
        exerciseCode: String,
        setIndex: Int
    ) -> (weight: Double, reps: Int)? {
        for session in sessionsNewestFirst(sessions) {
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }),
                  exercise.sets.indices.contains(setIndex)
            else { continue }
            let set = exercise.sets[setIndex]
            guard set.completed else { continue }
            return (set.weightKg, set.reps)
        }
        return nil
    }

    static func frequentWeight(
        sessions: [WorkoutSession],
        exerciseCode: String,
        setIndex: Int,
        limit: Int = 5
    ) -> Double? {
        let weights = sessionsNewestFirst(sessions).compactMap { session -> [Double]? in
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }),
                  exercise.sets.indices.contains(setIndex)
            else { return nil }
            let set = exercise.sets[setIndex]
            guard set.completed else { return nil }
            return [set.weightKg]
        }
        return frequentWeight(weightsNewestFirst: weights, limit: limit)
    }

    static func readyToProgress(sessions: [WorkoutSession], planID: UUID, exerciseCode: String) -> Bool {
        let relevant = sessionsNewestFirst(sessions).filter { $0.planID == planID }
        guard relevant.count >= 3 else { return false }
        return relevant.prefix(3).allSatisfy { session in
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }) else { return false }
            return metPlan(exercise.sets)
        }
    }

    static func volume(of sets: [WorkoutSessionSet]) -> Double {
        sets.filter(\.completed).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    static func volume(of exercise: WorkoutSessionExercise) -> Double {
        volume(of: exercise.sets)
    }

    static func volume(of session: WorkoutSession) -> Double {
        session.performedExercises.reduce(0) { $0 + volume(of: $1) }
    }

    static func volumeText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "de_DE")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
        return "\(number) kg"
    }

    static func isPersonalRecord(
        set: WorkoutSessionSet,
        exerciseCode: String,
        session: WorkoutSession,
        sessions: [WorkoutSession]
    ) -> Bool {
        guard set.completed else { return false }
        var bestWeight = 0.0
        var bestReps = 0
        var sawEarlier = false
        for past in sessions where past.id != session.id && past.finishedAt < session.finishedAt {
            guard let exercise = past.exercises.first(where: { $0.code == exerciseCode }) else { continue }
            for pastSet in exercise.sets where pastSet.completed {
                let weight = WorkoutFormat.rounded(pastSet.weightKg)
                if !sawEarlier || weight > bestWeight + 0.001 {
                    bestWeight = weight
                    bestReps = pastSet.reps
                    sawEarlier = true
                } else if abs(weight - bestWeight) < 0.001 {
                    bestReps = max(bestReps, pastSet.reps)
                }
            }
        }
        guard sawEarlier else { return false }
        let weight = WorkoutFormat.rounded(set.weightKg)
        if weight > bestWeight + 0.001 { return true }
        return abs(weight - bestWeight) < 0.001 && set.reps > bestReps
    }

    static func personalRecords(in session: WorkoutSession, sessions: [WorkoutSession]) -> [WorkoutPersonalRecord] {
        session.performedExercises.flatMap { exercise in
            exercise.sets.compactMap { set -> WorkoutPersonalRecord? in
                guard isPersonalRecord(set: set, exerciseCode: exercise.code, session: session, sessions: sessions) else { return nil }
                return WorkoutPersonalRecord(
                    setID: set.id,
                    exerciseCode: exercise.code,
                    exerciseName: exercise.name,
                    weightKg: set.weightKg,
                    reps: set.reps
                )
            }
        }
    }

    static func grade(of session: WorkoutSession, comparedWith sessions: [WorkoutSession]) -> WorkoutGrade {
        let previous = sessions
            .filter { $0.planID == session.planID && $0.id != session.id && $0.finishedAt < session.finishedAt }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(3)
        guard !previous.isEmpty else { return .strong }
        let baseline = previous.reduce(0) { $0 + volume(of: $1) } / Double(previous.count)
        guard baseline > 0 else { return .strong }
        let ratio = volume(of: session) / baseline
        if ratio < 0.9 { return .weak }
        if ratio <= 1.1 { return .average }
        return .strong
    }

    static func motivation(for grade: WorkoutGrade, seed: Int) -> String {
        let lines: [String]
        switch grade {
        case .weak:
            lines = [
                L("Du Weichei.", "That was soft."),
                L("Mehr Ausrede als Eisen.", "More excuse than iron."),
                L("Schwach. Hoch da.", "Weak. Get up.")
            ]
        case .average:
            lines = [
                L("Da geht noch mehr.", "There is more in you."),
                L("Solide. Trotzdem zu wenig.", "Solid. Still not enough."),
                L("Nicht schlecht. Nicht gut.", "Not bad. Not good.")
            ]
        case .strong:
            lines = [
                L("Du Maschine, weiter so.", "Machine. Keep going."),
                L("Stark. Jetzt noch einer.", "Strong. Now one more."),
                L("So wird das was.", "That's how it's done.")
            ]
        }
        let index = Int(UInt(bitPattern: seed) % UInt(lines.count))
        return lines[index]
    }
}

enum WorkoutGrade {
    case weak
    case average
    case strong
}

struct WorkoutPersonalRecord: Identifiable {
    var setID: UUID
    var exerciseCode: String
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var id: String { "\(exerciseCode)-\(setID.uuidString)" }
}
