import Foundation
import LififyCore

/// Suggests the next weight of an exercise and tracks its training volume.
public enum ProgressiveOverload {
    public static let stepKey = "lifify.overloadStepKg"
    public static let defaultStepKg = 2.5

    /// The next weight, based on the last session with this exercise.
    public struct Suggestion: Equatable {
        public let weightKg: Double
        public let lastWeightKg: Double
        public let raised: Bool

        /// Creates a suggestion.
        public init(weightKg: Double, lastWeightKg: Double, raised: Bool) {
            self.weightKg = weightKg
            self.lastWeightKg = lastWeightKg
            self.raised = raised
        }
    }

    /// The volume of an exercise in one session.
    public struct VolumePoint: Identifiable, Equatable {
        public let id: UUID
        public let date: Date
        public let volume: Double
    }

    /// The chosen weight step, or the default.
    public static var stepKg: Double {
        let stored = AppDefaults.store.object(forKey: stepKey) as? Double ?? defaultStepKg
        return stored > 0 ? stored : defaultStepKg
    }

    /// Suggests a higher weight when the last session reached every target, or the same one.
    ///
    /// - Parameters:
    ///   - sessions: All finished sessions.
    ///   - exerciseCode: The exercise.
    ///   - step: The weight increase.
    /// - Returns: The suggestion, or `nil` without a weighted set in the history.
    public static func suggestion(sessions: [WorkoutSession], exerciseCode: String, step: Double) -> Suggestion? {
        guard let sets = lastSets(sessions: sessions, exerciseCode: exerciseCode) else { return nil }
        let last = WorkoutFormat.rounded(sets.filter(\.completed).map(\.weightKg).max() ?? 0)
        guard last > 0 else { return nil }
        let reachedAll = sets.allSatisfy { $0.completed && $0.reps >= $0.targetReps }
        let next = reachedAll ? WorkoutFormat.rounded(last + step) : last
        return Suggestion(weightKg: next, lastWeightKg: last, raised: reachedAll)
    }

    /// Lists the volume of an exercise per session, newest first.
    ///
    /// - Parameters:
    ///   - sessions: All finished sessions.
    ///   - exerciseCode: The exercise.
    ///   - limit: The maximum number of sessions.
    /// - Returns: Sessions in which the exercise has completed sets.
    public static func volumeHistory(sessions: [WorkoutSession], exerciseCode: String, limit: Int = 6) -> [VolumePoint] {
        let points = WorkoutProgress.sessionsNewestFirst(sessions).compactMap { session -> VolumePoint? in
            guard let exercise = session.exercises.first(where: { $0.code == exerciseCode }),
                  exercise.sets.contains(where: \.completed)
            else { return nil }
            return VolumePoint(id: session.id, date: session.finishedAt, volume: WorkoutProgress.volume(of: exercise))
        }
        return Array(points.prefix(limit))
    }

    /// Returns the sets of the newest session in which the exercise was performed.
    private static func lastSets(sessions: [WorkoutSession], exerciseCode: String) -> [WorkoutSessionSet]? {
        for session in WorkoutProgress.sessionsNewestFirst(sessions) {
            if let exercise = session.exercises.first(where: { $0.code == exerciseCode }),
               exercise.sets.contains(where: \.completed) {
                return exercise.sets
            }
        }
        return nil
    }
}
