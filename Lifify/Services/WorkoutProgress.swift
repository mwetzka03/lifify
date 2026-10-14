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
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }) else { continue }
            let completed = exercise.sets.filter(\.completed)
            guard completed.indices.contains(setIndex) else { continue }
            return (completed[setIndex].weightKg, completed[setIndex].reps)
        }
        return nil
    }

    static func frequentWeight(
        sessions: [WorkoutSession],
        exerciseCode: String,
        limit: Int = 5
    ) -> Double? {
        let weights = sessionsNewestFirst(sessions).compactMap { session -> [Double]? in
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }) else { return nil }
            let completed = exercise.sets.filter(\.completed).map(\.weightKg)
            return completed.isEmpty ? nil : completed
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
}
