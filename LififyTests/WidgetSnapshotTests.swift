import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// The widgets read a snapshot, and only the app books their check-offs.
    @Suite("Widget snapshot")
    @MainActor
    struct WidgetSnapshotTests {
        private let now = date(2026, 3, 18)

        /// A temporary shared folder.
        private func folder() throws -> URL {
            let url = AppFiles.supportDirectory.appendingPathComponent("widget", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @Test func amountsStayOutWhileTheLockHidesThem() async throws {
            try await withTestStore { store in
                store.context.insert(Account(name: "Giro", isMain: true))
                store.context.insert(LedgerEntry(date: date(2026, 3, 1), title: "Lohn", amountCents: 10_000, kind: .income))
                try store.context.save()
                #expect(WidgetPublisher.snapshot(context: store.context, plans: [], now: now).finance == nil)
                store.defaults.set(true, forKey: FinanceLockSettings.widgetValuesKey)
                #expect(WidgetPublisher.snapshot(context: store.context, plans: [], now: now).finance != nil)
                store.defaults.set(false, forKey: FinanceLockSettings.widgetValuesKey)
                store.defaults.set(false, forKey: FinanceLockSettings.enabledKey)
                #expect(WidgetPublisher.snapshot(context: store.context, plans: [], now: now).finance != nil)
            }
        }

        @Test func listsTodaysAndTomorrowsChallengesWithTheirRules() async throws {
            try await withTestStore { store in
                let reading = ChallengeItem(title: "Lesen", recurrence: .daily, startDate: date(2026, 3, 1))
                let sport = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: date(2026, 3, 1))
                let abstinence = ChallengeItem(title: "Rauchfrei", category: .abstinence, startDate: date(2026, 3, 1))
                [reading, sport, abstinence].forEach(store.context.insert)
                let plan = UUID()
                WorkoutLinkStore.link(planID: plan, challengeID: sport.id)
                try store.context.save()
                let snapshot = WidgetPublisher.snapshot(context: store.context, plans: [], now: now)
                let today = snapshot.challenges(on: now)
                #expect(today.map(\.title) == ["Lesen", "Sport"])
                #expect(today[0].canCheckOff)
                #expect(!today[1].canCheckOff)
                #expect(today[1].planID == plan)
                #expect(snapshot.challenges(on: days(1, after: now)).count == 2)
            }
        }

        @Test func aWidgetCheckOffIsBookedOnceByTheApp() async throws {
            try await withTestStore { store in
                let shared = try folder()
                let challenge = ChallengeItem(title: "Lesen", recurrence: .daily, startDate: date(2026, 3, 1), rewardCoins: 10)
                store.context.insert(challenge)
                try store.context.save()
                WidgetStore.write(WidgetPublisher.snapshot(context: store.context, plans: [], now: now), in: shared)
                let tap = WidgetCheckOff(challengeID: challenge.id, date: now)
                WidgetStore.enqueue(tap, in: shared)
                WidgetStore.enqueue(tap, in: shared)
                #expect(WidgetStore.pending(in: shared).count == 1)
                #expect(WidgetStore.read(in: shared)?.challenges(on: now).isEmpty == true)
                try #expect(store.wallet() == 0)
                WidgetPublisher.applyPending(context: store.context, folder: shared)
                try #expect(store.wallet() == 10)
                #expect(WidgetStore.pending(in: shared).isEmpty)
                WidgetPublisher.applyPending(context: store.context, folder: shared)
                try #expect(store.wallet() == 10)
            }
        }

        @Test func aLockedSportChallengeStaysOpenThroughTheQueue() async throws {
            try await withTestStore { store in
                let shared = try folder()
                let sport = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: date(2026, 3, 1))
                store.context.insert(sport)
                WorkoutLinkStore.link(planID: UUID(), challengeID: sport.id)
                try store.context.save()
                WidgetStore.enqueue(WidgetCheckOff(challengeID: sport.id, date: now), in: shared)
                WidgetPublisher.applyPending(context: store.context, folder: shared)
                try #expect(store.all(ChallengeCompletion.self).isEmpty)
            }
        }

        @Test func aNegativeWalletShowsTheLockedShop() async throws {
            try await withTestStore { store in
                store.context.insert(CoinTransaction(title: "Kauf", amount: -5))
                try store.context.save()
                #expect(WidgetPublisher.snapshot(context: store.context, plans: [], now: now).isShopLocked)
            }
        }

        @Test func aTrainingLinkOpensOnlyItsPlan() throws {
            let plan = UUID()
            let url = try #require(WidgetRoute.url(plan: plan))
            #expect(WidgetRoute.plan(in: WidgetRoute.route(from: url)) == plan)
            #expect(WidgetRoute.route(from: try #require(URL(string: "lifify://notice?account=a&text=b"))) == nil)
            #expect(WidgetRoute.plan(in: "periodReview") == nil)
        }

        @Test func theLiveActivityFollowsTheOpenSet() {
            let first = WorkoutSessionExercise(code: "a", name: "Bank", restSeconds: 60, sets: [
                WorkoutSessionSet(weightKg: 50, reps: 8, completed: true, targetWeightKg: 50, targetReps: 8),
                WorkoutSessionSet(weightKg: 50, reps: 8, completed: false, targetWeightKg: 50, targetReps: 8)
            ])
            var session = WorkoutSession(plan: WorkoutPlan(name: "Push"), now: now)
            session.exercises = [first]
            let state = WorkoutActivityProgress.state(of: session, restEndsAt: now)
            #expect(state.exercise == "Bank")
            #expect(state.setNumber == 2)
            #expect(state.setCount == 2)
            #expect(state.restEndsAt == now)
            session.exercises[0].sets[1].completed = true
            #expect(WorkoutActivityProgress.state(of: session, restEndsAt: nil).setNumber == 2)
        }

        @Test func theNextTrainingComesFromALinkedSlot() async throws {
            try await withTestStore { store in
                let plan = WorkoutPlan(name: "Push")
                let event = ChallengeCalendarEvent(title: "Sport", startDate: date(2026, 3, 19, 18), endDate: date(2026, 3, 19, 19))
                store.context.insert(event)
                WorkoutLinkStore.link(planID: plan.id, eventID: event.id, managed: false)
                try store.context.save()
                let next = WidgetPublisher.snapshot(context: store.context, plans: [plan], now: now).nextTraining
                #expect(next?.title == "Push")
                #expect(next?.planID == plan.id)
            }
        }
    }
}
