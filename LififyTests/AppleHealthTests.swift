import Foundation
import LififyCore
import LififyHealth
import Testing
@testable import Lifify

/// A scripted Apple Health.
@MainActor
private final class FakeHealthSource: HealthDataSource {
    var isAvailable = true
    var grants = true
    var weight: (kilograms: Double, date: Date)?
    var saved: [(Date, Date)] = []
    var summaryValue = HealthSummary(steps: [HealthDayValue(date: date(2026, 3, 18), value: 9_000)])

    func requestAccess() async -> Bool { grants }
    func latestWeight() async -> (kilograms: Double, date: Date)? { weight }
    func summary(days: Int) async -> HealthSummary { summaryValue }
    func saveWorkout(start: Date, end: Date) async -> Bool {
        saved.append((start, end))
        return true
    }
}

extension LififyRuleTests {
    /// Apple Health stays silent until allowed and then syncs each value once.
    @Suite("Apple Health")
    @MainActor
    struct AppleHealthTests {
        /// Runs with a scripted source.
        private func withSource(_ body: (TestStore, FakeHealthSource) async throws -> Void) async throws {
            let previous = AppleHealthSync.source
            let fake = FakeHealthSource()
            AppleHealthSync.source = fake
            defer { AppleHealthSync.source = previous }
            try await withTestStore { try await body($0, fake) }
        }

        /// A finished session.
        private func session() -> WorkoutSession {
            var session = WorkoutSession(plan: WorkoutPlan(name: "Push"), now: date(2026, 3, 18, 10))
            session.finishedAt = date(2026, 3, 18, 11)
            return session
        }

        @Test func withoutPermissionNothingHappens() async throws {
            try await withSource { store, fake in
                fake.weight = (80, date(2026, 3, 18))
                await AppleHealthSync.refreshWeight()
                await AppleHealthSync.export(session())
                #expect(store.defaults.object(forKey: UserBody.weightKey) == nil)
                #expect(fake.saved.isEmpty)
                let summary = await AppleHealthSync.summary()
                #expect(summary == nil)
            }
        }

        @Test func aDeniedRequestStaysOff() async throws {
            try await withSource { _, fake in
                fake.grants = false
                let enabled = await AppleHealthSync.enable()
                #expect(!enabled)
                #expect(!AppleHealthSync.isEnabled)
            }
        }

        @Test func aNewerWeightUpdatesTheBodyData() async throws {
            try await withSource { _, fake in
                fake.weight = (80.44, date(2026, 3, 18))
                _ = await AppleHealthSync.enable()
                #expect(UserBody.current().weightKg == 80.4)
                fake.weight = (70, date(2026, 3, 1))
                await AppleHealthSync.refreshWeight()
                #expect(UserBody.current().weightKg == 80.4)
                fake.weight = (79, date(2026, 3, 19))
                await AppleHealthSync.refreshWeight()
                #expect(UserBody.current().weightKg == 79)
            }
        }

        @Test func aWorkoutIsSavedOnce() async throws {
            try await withSource { _, fake in
                _ = await AppleHealthSync.enable()
                let finished = session()
                await AppleHealthSync.export(finished)
                await AppleHealthSync.export(finished)
                #expect(fake.saved.count == 1)
                #expect(fake.saved.first?.0 == finished.startedAt)
            }
        }

        @Test func theSummaryComesFromTheSource() async throws {
            try await withSource { _, _ in
                _ = await AppleHealthSync.enable()
                let summary = await AppleHealthSync.summary()
                #expect(summary?.steps.first?.value == 9_000)
            }
        }
    }
}
