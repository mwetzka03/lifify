import Foundation
import LififyCore
import LififyHealth
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// The next weight follows the last session, and the volume is listed per session.
    @Suite("Progressive overload")
    @MainActor
    struct ProgressiveOverloadTests {
        /// Builds a finished session with one exercise.
        private func session(_ day: Int, sets: [(weight: Double, reps: Int, target: Int, done: Bool)], code: String = "bench") -> WorkoutSession {
            var session = WorkoutSession(plan: WorkoutPlan(name: "Push"), now: date(2026, 3, day))
            session.finishedAt = date(2026, 3, day, 13)
            session.exercises = [WorkoutSessionExercise(code: code, name: "Bank", restSeconds: 90, sets: sets.map {
                WorkoutSessionSet(weightKg: $0.weight, reps: $0.reps, completed: $0.done, targetWeightKg: $0.weight, targetReps: $0.target)
            })]
            return session
        }

        @Test func reachedTargetsRaiseTheWeight() {
            let last = session(3, sets: [(60, 8, 8, true), (60, 9, 8, true)])
            let next = ProgressiveOverload.suggestion(sessions: [last], exerciseCode: "bench", step: 2.5)
            #expect(next == .init(weightKg: 62.5, lastWeightKg: 60, raised: true))
        }

        @Test func aMissedRepKeepsTheWeight() {
            let older = session(1, sets: [(55, 8, 8, true)])
            let last = session(3, sets: [(60, 8, 8, true), (60, 7, 8, true)])
            let next = ProgressiveOverload.suggestion(sessions: [older, last], exerciseCode: "bench", step: 2.5)
            #expect(next == .init(weightKg: 60, lastWeightKg: 60, raised: false))
        }

        @Test func anUnfinishedSetKeepsTheWeight() {
            let last = session(3, sets: [(60, 8, 8, true), (60, 8, 8, false)])
            #expect(ProgressiveOverload.suggestion(sessions: [last], exerciseCode: "bench", step: 2.5)?.raised == false)
        }

        @Test func aSessionWithoutTheExerciseIsSkipped() {
            let bench = session(1, sets: [(50, 8, 8, true)])
            let other = session(3, sets: [(20, 8, 8, true)], code: "row")
            #expect(ProgressiveOverload.suggestion(sessions: [bench, other], exerciseCode: "bench", step: 5)?.weightKg == 55)
            #expect(ProgressiveOverload.suggestion(sessions: [other], exerciseCode: "bench", step: 5) == nil)
        }

        @Test func bodyweightGetsNoSuggestion() {
            let last = session(3, sets: [(0, 12, 10, true)])
            #expect(ProgressiveOverload.suggestion(sessions: [last], exerciseCode: "bench", step: 2.5) == nil)
        }

        @Test func volumeCountsCompletedSetsNewestFirst() {
            let older = session(1, sets: [(50, 10, 10, true), (50, 10, 10, false)])
            let newer = session(3, sets: [(60, 5, 5, true), (60, 5, 5, true)])
            let points = ProgressiveOverload.volumeHistory(sessions: [older, newer], exerciseCode: "bench")
            #expect(points.map(\.volume) == [600, 500])
        }

        @Test func theStepFollowsTheSetting() async throws {
            try await withTestStore { store in
                #expect(ProgressiveOverload.stepKg == 2.5)
                store.defaults.set(5.0, forKey: ProgressiveOverload.stepKey)
                #expect(ProgressiveOverload.stepKg == 5)
            }
        }
    }
}
