import Foundation
import LififyChallenges
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

extension LififyRuleTests {
    /// The step card's numbers leave out the unfinished day and days without data.
    @Suite("Step statistics")
    struct StepStatsTests {
        private let now = date(2026, 3, 18, 15)

        /// A value some days before `now`.
        private func day(_ offset: Int, _ steps: Double) -> HealthDayValue {
            HealthDayValue(date: days(-offset, after: date(2026, 3, 18)), value: steps)
        }

        @Test func averagesLeaveOutTodayAndEmptyDays() {
            let values = [day(0, 2_000), day(1, 8_000), day(2, 10_000), day(10, 6_000)]
            let stats = StepStats.make(values, now: now)
            #expect(stats.today == 2_000)
            #expect(stats.weekAverage == 9_000)
            #expect(stats.monthAverage == 8_000)
            #expect(stats.best?.value == 10_000)
        }

        @Test func withoutDataThereIsNoAverage() {
            let stats = StepStats.make([], now: now)
            #expect(stats.today == 0)
            #expect(stats.weekAverage == nil)
            #expect(stats.monthAverage == nil)
        }

        @Test func olderPagesShowTheWeeksBefore() {
            let values = [day(7, 1_000), day(13, 3_000), day(14, 9_000)]
            let page = StepStats.chartDays(values, count: 7, page: 1, now: now)
            #expect(page.count == 7)
            #expect(Calendar.current.isDate(page.last!.date, inSameDayAs: days(-7, after: date(2026, 3, 18))))
            #expect(page.first?.value == 3_000)
            #expect(StepStats.average(of: page, now: now) == 2_000)
            #expect(StepStats.hasData(values, count: 7, page: 2, now: now))
            #expect(!StepStats.hasData(values, count: 7, page: 3, now: now))
        }

        @Test func theChartFillsMissingDaysWithZero() {
            let chart = StepStats.chartDays([day(0, 500), day(2, 700)], count: 7, now: now)
            #expect(chart.count == 7)
            #expect(chart.last?.value == 500)
            #expect(chart[4].value == 700)
            #expect(chart[5].value == 0)
            #expect(Calendar.current.isDate(chart[0].date, inSameDayAs: days(-6, after: date(2026, 3, 18))))
        }
    }
}

extension LififyRuleTests {
    /// Home shows the trainings the calendar plans.
    @Suite("Training agenda")
    @MainActor
    struct TrainingAgendaTests {
        @Test func eventsWithLinkedPlansBecomeTrainings() async throws {
            try await withTestStore { _ in
                let push = WorkoutPlan(name: "Push")
                let pull = WorkoutPlan(name: "Pull")
                let monday = ChallengeCalendarEvent(title: "Sport", startDate: date(2026, 3, 16, 18), endDate: date(2026, 3, 16, 19))
                let other = ChallengeCalendarEvent(title: "Zahnarzt", startDate: date(2026, 3, 17, 9), endDate: date(2026, 3, 17, 10))
                WorkoutLinkStore.link(planID: push.id, eventID: monday.id, managed: false)
                let challenge = UUID()
                WorkoutLinkStore.link(planID: pull.id, challengeID: challenge)
                let wednesday = ChallengeCalendarEvent(title: "Sport", startDate: date(2026, 3, 18, 7), endDate: date(2026, 3, 18, 8))
                wednesday.linkedChallengeID = challenge
                var session = WorkoutSession(plan: push, now: date(2026, 3, 16, 18))
                session.finishedAt = date(2026, 3, 16, 19)
                let items = TrainingAgenda.items(
                    events: [wednesday, other, monday], plans: [push, pull], sessions: [session],
                    from: date(2026, 3, 16), to: date(2026, 3, 23)
                )
                #expect(items.map(\.planName) == ["Push", "Pull"])
                #expect(items.map(\.isDone) == [true, false])
                #expect(TrainingAgenda.items(events: [monday], plans: [push], sessions: [], from: date(2026, 3, 17), to: date(2026, 3, 18)).isEmpty)
            }
        }

        @Test func aRangeSumsStepsAndAveragesFinishedDays() {
            let values = [
                HealthDayValue(date: date(2026, 3, 16), value: 4_000),
                HealthDayValue(date: date(2026, 3, 17), value: 6_000),
                HealthDayValue(date: date(2026, 3, 18), value: 1_000)
            ]
            let week = StepStats.range(values, from: date(2026, 3, 16), to: date(2026, 3, 23), now: date(2026, 3, 18, 12))
            #expect(week.total == 11_000)
            #expect(week.average == 5_000)
        }
    }
}
