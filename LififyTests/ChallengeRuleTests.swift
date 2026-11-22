import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Test isolation")
    @MainActor
    struct IsolationTests {
        @Test func writesStayOutOfStandardDefaults() async throws {
            let before = UserDefaults.standard.data(forKey: "lifify.streakStates")
            try await withTestStore { store in
                StreakSettings.setEnabled(true, for: UUID())
                #expect(store.defaults.data(forKey: "lifify.streakStates") != nil)
                #expect(AppDefaults.store === store.defaults)
            }
            #expect(UserDefaults.standard.data(forKey: "lifify.streakStates") == before)
            #expect(AppDefaults.store === UserDefaults.standard)
        }

        @Test func cachesDoNotLeakBetweenStores() async throws {
            let id = UUID()
            try await withTestStore { _ in StreakSettings.setEnabled(true, for: id) }
            try await withTestStore { _ in #expect(!StreakSettings.isEnabled(for: id)) }
        }
    }

    @Suite("Coins and wallet")
    @MainActor
    struct CoinTests {
        private func toggle(_ challenge: ChallengeItem, on day: Date, _ store: TestStore) throws {
            ChallengeService.toggleCompletion(
                challenge: challenge,
                date: day,
                completions: try store.all(),
                transactions: try store.all(),
                context: store.context
            )
        }

        @Test func checkingOffPaysAndUncheckingTakesBack() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let challenge = ChallengeItem(title: "Lesen", category: .todo, startDate: day, rewardCoins: 10)
                store.context.insert(challenge)
                try toggle(challenge, on: day, store)
                try #expect(store.wallet() == 10)
                try #expect(store.all(ChallengeCompletion.self).count == 1)
                try toggle(challenge, on: day, store)
                try #expect(store.wallet() == 0)
                try #expect(store.all(ChallengeCompletion.self).isEmpty)
            }
        }

        @Test func walletMayGoNegativeAfterPurchase() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let challenge = ChallengeItem(title: "Lesen", category: .todo, startDate: day, rewardCoins: 10)
                let reward = RewardItem(title: "Kino", price: 10)
                store.context.insert(challenge)
                store.context.insert(reward)
                try toggle(challenge, on: day, store)
                try #expect(ChallengeService.purchase(reward: reward, transactions: store.all(), context: store.context))
                try #expect(store.wallet() == 0)
                try toggle(challenge, on: day, store)
                try #expect(store.wallet() == -10)
            }
        }

        @Test func purchaseNeedsEnoughCoins() async throws {
            try await withTestStore { store in
                let reward = RewardItem(title: "Kino", price: 10)
                store.context.insert(reward)
                store.context.insert(CoinTransaction(title: "Start", amount: 9))
                try #expect(!ChallengeService.purchase(reward: reward, transactions: store.all(), context: store.context))
                try #expect(store.wallet() == 9)
                try #expect(store.all(RewardPurchase.self).isEmpty)
            }
        }

        @Test func pastDaysCanBeCheckedOff() async throws {
            try await withTestStore { store in
                let start = date(2026, 3, 2)
                let challenge = ChallengeItem(title: "Laufen", category: .habit, recurrence: .daily, startDate: start)
                store.context.insert(challenge)
                let past = days(1, after: start)
                try toggle(challenge, on: past, store)
                try #expect(ChallengeService.isCompleted(challenge, on: past, completions: store.all()))
            }
        }

        @Test func linkedSportAndAbstinenceCannotBeCheckedByHand() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let sport = ChallengeItem(title: "Sport", category: .sport, startDate: day)
                let abstinence = ChallengeItem(title: "Kein Zucker", category: .abstinence, startDate: day)
                store.context.insert(sport)
                store.context.insert(abstinence)
                WorkoutLinkStore.link(planID: UUID(), challengeID: sport.id)
                try toggle(sport, on: day, store)
                try toggle(abstinence, on: day, store)
                try #expect(store.all(ChallengeCompletion.self).isEmpty)
            }
        }

        @Test func automaticCompletionPaysOnce() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let challenge = ChallengeItem(title: "Sport", category: .sport, startDate: day, rewardCoins: 25)
                store.context.insert(challenge)
                try #expect(ChallengeService.markCompletedIfNeeded(challenge: challenge, date: day, completions: store.all(), context: store.context))
                try #expect(!ChallengeService.markCompletedIfNeeded(challenge: challenge, date: day, completions: store.all(), context: store.context))
                try #expect(store.wallet() == 25)
            }
        }
    }

    @Suite("Streaks, freezes and multiplier")
    @MainActor
    struct StreakTests {
        private let start = date(2026, 3, 2)

        private func state(purchased: Int = 0) -> StreakSettings.State {
            StreakSettings.State(enabled: true, enabledAt: start, purchased: purchased, usedPeriodKeys: [])
        }

        private func status(
            _ challenge: ChallengeItem,
            done offsets: [Int],
            through offset: Int,
            purchased: Int = 0,
            meals: ((Date) -> Int)? = nil
        ) -> ChallengeService.StreakStatus {
            ChallengeService.status(
                for: challenge,
                endingOn: days(offset, after: start),
                completions: offsets.map {
                    ChallengeCompletion(challengeID: challenge.id, date: days($0, after: start), earnedCoins: 0)
                },
                events: [],
                streakState: state(purchased: purchased),
                usesStoredState: false,
                confirmedMeals: meals
            )
        }

        private func daily(_ identifier: String? = nil) -> ChallengeItem {
            ChallengeItem(title: "Täglich", category: .habit, recurrence: .daily, startDate: start, externalIdentifier: identifier)
        }

        @Test func consecutiveDaysCount() async throws {
            try await withTestStore { _ in
                let result = status(daily(), done: [0, 1, 2], through: 2)
                #expect(result.count == 3)
                #expect(result.required == 1)
                #expect(result.done == 1)
                #expect(result.freezeKeys.isEmpty)
            }
        }

        @Test func missedDayUsesFreeze() async throws {
            try await withTestStore { _ in
                let result = status(daily(), done: [0, 2], through: 2)
                #expect(result.count == 2)
                #expect(result.freezeKeys == ["d:2026-03-03"])
            }
        }

        @Test func thirdMissResetsWithoutPurchasedFreeze() async throws {
            try await withTestStore { _ in
                let result = status(daily(), done: [0], through: 4)
                #expect(result.count == 0)
                #expect(result.freezeKeys.count == StreakFreeze.startingCount)
            }
        }

        @Test func purchasedFreezeCoversThirdMiss() async throws {
            try await withTestStore { _ in
                let result = status(daily(), done: [0], through: 4, purchased: 1)
                #expect(result.count == 1)
                #expect(result.freezeKeys.count == 3)
            }
        }

        @Test func weeklyQuotaAcceptsAnyDaysOfTheWeek() async throws {
            try await withTestStore { _ in
                let challenge = ChallengeItem(
                    title: "Dreimal",
                    category: .habit,
                    recurrence: .weekly,
                    startDate: start,
                    weeklyDays: [2, 4, 6]
                )
                let result = status(challenge, done: [1, 3, 5], through: 7)
                #expect(result.count == 3)
                #expect(result.required == 3)
                #expect(result.done == 0)
                #expect(result.freezeKeys.isEmpty)
            }
        }

        @Test func nutritionDayWithoutMealsIsNoMiss() async throws {
            try await withTestStore { _ in
                let result = status(daily("nutrition:calories"), done: [0], through: 3) { _ in 0 }
                #expect(result.count == 1)
                #expect(result.freezeKeys.isEmpty)
            }
        }

        @Test func buyingFreezeCostsRewardTimesFactor() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Täglich", category: .habit, recurrence: .daily, startDate: start, rewardCoins: 10)
                store.context.insert(challenge)
                StreakSettings.setEnabled(true, for: challenge.id)
                store.context.insert(CoinTransaction(title: "Start", amount: 99))
                try #expect(!ChallengeService.purchaseFreeze(challenge: challenge, transactions: store.all(), context: store.context))
                store.context.insert(CoinTransaction(title: "Mehr", amount: 1))
                try #expect(ChallengeService.purchaseFreeze(challenge: challenge, transactions: store.all(), context: store.context))
                try #expect(store.wallet() == 0)
                #expect(StreakSettings.state(for: challenge.id)?.purchased == 1)
            }
        }

        @Test(arguments: [(4, 1.0), (5, 1.1), (9, 1.1), (10, 1.2), (100, 2.0), (999, 2.75), (1000, 3.0)])
        func multiplierFollowsThresholds(streak: Int, factor: Double) async throws {
            try await withTestStore { _ in
                #expect(StreakSettings.multiplier(forStreak: streak) == factor)
            }
        }

        @Test func customMultiplierWins() async throws {
            try await withTestStore { _ in
                StreakSettings.setMultiplier(2, for: 5)
                #expect(StreakSettings.multiplier(forStreak: 5) == 2)
                #expect(StreakSettings.multiplier(forStreak: 10) == 1.2)
            }
        }

        @Test func projectedCoinsIncludeTheDayBeingCompleted() async throws {
            try await withTestStore { _ in
                let challenge = daily()
                StreakSettings.restoreState(BackupRecord(
                    type: "streakState",
                    id: challenge.id,
                    integers: [0],
                    booleans: [true],
                    dates: [start]
                ))
                let completions = (0..<4).map {
                    ChallengeCompletion(challengeID: challenge.id, date: days($0, after: start), earnedCoins: 10)
                }
                let coins = ChallengeService.projectedCoins(
                    challenge: challenge,
                    on: days(4, after: start),
                    completions: completions,
                    events: []
                )
                #expect(coins == 11)
            }
        }
    }

    @Suite("Abstinence")
    @MainActor
    struct AbstinenceTests {
        private let start = date(2026, 3, 2)

        @Test func settlePaysEachDayOnce() async throws {
            try await withTestStore { store in
                let challenge = ChallengeItem(title: "Kein Zucker", category: .abstinence, startDate: start, rewardCoins: 5)
                store.context.insert(challenge)
                let now = start.addingTimeInterval(30 * 60)
                AbstinenceService.settle(context: store.context, now: now)
                AbstinenceService.settle(context: store.context, now: now)
                try #expect(store.wallet() == 5)
                try #expect(store.all(ChallengeCompletion.self).count == 1)
            }
        }

        @Test func planSkipsPaidDaysAndBonuses() {
            let now = days(3, after: start).addingTimeInterval(3_600)
            let fresh = AbstinenceRules.plan(start: start, now: now, completedDays: [], awarded: [])
            #expect(fresh.days.count == 4)
            #expect(fresh.milestones == [.hour1, .hour2, .hour4, .hour8, .hour24, .hour72])
            let paid = AbstinenceRules.plan(
                start: start,
                now: now,
                completedDays: [Calendar.current.startOfDay(for: start)],
                awarded: ["1h"]
            )
            #expect(paid.days.count == 3)
            #expect(paid.milestones.first == .hour2)
        }

        @Test func bonusFollowsDifficulty() async throws {
            try await withTestStore { _ in
                #expect(AbstinenceRules.bonusCoins(base: 10, multiplier: AbstinenceSettings.multiplier(for: .medium, milestone: .hour1)) == 20)
                #expect(AbstinenceRules.bonusCoins(base: 5, multiplier: AbstinenceSettings.multiplier(for: .easy, milestone: .hour1)) == 3)
                #expect(AbstinenceRules.bonusCoins(base: 0, multiplier: 12) == 0)
            }
        }
    }

    @Suite("Due dates")
    @MainActor
    struct DueTests {
        private let start = date(2026, 3, 2)

        private func due(_ challenge: ChallengeItem, _ day: Date) -> Bool {
            ChallengeService.isDue(challenge, on: day)
        }

        @Test func onceIsDueOnItsDayOnly() async throws {
            try await withTestStore { _ in
                let challenge = ChallengeItem(title: "Einmal", recurrence: .none, startDate: start)
                #expect(due(challenge, start))
                #expect(!due(challenge, days(1, after: start)))
                #expect(!due(ChallengeItem(title: "Ohne Datum", recurrence: .none, startDate: nil), start))
            }
        }

        @Test func dailyRespectsRangeAndArchive() async throws {
            try await withTestStore { _ in
                let end = days(2, after: start)
                let challenge = ChallengeItem(title: "Täglich", recurrence: .daily, startDate: start, endDate: end)
                #expect(!due(challenge, days(-1, after: start)))
                #expect(due(challenge, end))
                #expect(!due(challenge, days(3, after: start)))
                #expect(!due(ChallengeItem(title: "Archiv", recurrence: .daily, startDate: start, isArchived: true), start))
            }
        }

        @Test func weeklyMonthlyYearlyAndIrregular() async throws {
            try await withTestStore { _ in
                let weekly = ChallengeItem(title: "Woche", recurrence: .weekly, startDate: start, weeklyDays: [2])
                #expect(due(weekly, days(7, after: start)))
                #expect(!due(weekly, days(1, after: start)))
                let monthly = ChallengeItem(title: "Monat", recurrence: .monthly, startDate: start)
                #expect(due(monthly, date(2026, 4, 2)))
                #expect(!due(monthly, date(2026, 4, 3)))
                let yearly = ChallengeItem(title: "Jahr", recurrence: .yearly, startDate: start)
                #expect(due(yearly, date(2027, 3, 2)))
                #expect(!due(yearly, date(2027, 4, 2)))
                #expect(due(ChallengeItem(title: "Frei", recurrence: .irregular, startDate: start), days(5, after: start)))
            }
        }
    }

    @Suite("Time slots and groups")
    @MainActor
    struct TimeSlotTests {
        @Test func slotFillsUntilMinutesAreUsed() {
            #expect(ChallengeTimeRules.fitCount(minutes: [30, 45, 60], slotMinutes: 100) == 2)
            #expect(ChallengeTimeRules.fitCount(minutes: [30, 90, 10], slotMinutes: 100) == 1)
            #expect(ChallengeTimeRules.remaining(slotMinutes: 120, linkedMinutes: [75, 0]) == 45)
            #expect(ChallengeTimeRules.remaining(slotMinutes: 30, linkedMinutes: [45]) == 0)
        }

        @Test func sportAndAbstinenceAreExclusiveWithoutMinutes() {
            for category in [ChallengeCategory.sport, .abstinence] {
                #expect(!ChallengeTimeRules.allowsTime(category))
                #expect(ChallengeTimeRules.isExclusiveLink(category: category, identifier: nil))
            }
            #expect(ChallengeTimeRules.allowsTime(.todo))
            #expect(!ChallengeTimeRules.isExclusiveLink(category: .todo, identifier: nil))
        }

        @Test func onlyOneTimeChallengesShareAnEvent() {
            #expect(EventRewrite.canShare(adding: .none, others: [.none]))
            #expect(EventRewrite.canShare(adding: .daily, others: []))
            #expect(!EventRewrite.canShare(adding: .daily, others: [.none]))
            #expect(!EventRewrite.canShare(adding: .none, others: [.weekly]))
        }

        @Test func finishedEventMovesToActualDuration() throws {
            let first = date(2026, 3, 2, 10, 0)
            let last = date(2026, 3, 2, 11, 30)
            let window = try #require(EventRewrite.window(checkedOffAt: [first, last], durations: [20, 25]))
            #expect(window.end == last)
            #expect(window.start == last.addingTimeInterval(-45 * 60))
            let one = UUID()
            let two = UUID()
            #expect(!EventRewrite.ready(memberIDs: [one, two], completedIDs: [one]))
            #expect(EventRewrite.ready(memberIDs: [one, two], completedIDs: [one, two]))
        }

        @Test func repeatingMemberDoesNotResizeTheEvent() async throws {
            try await withTestStore { store in
                let start = date(2026, 3, 2, 10)
                let end = date(2026, 3, 2, 11)
                let challenge = ChallengeItem(title: "Täglich", recurrence: .daily, startDate: start)
                let event = ChallengeCalendarEvent(title: "Termin", startDate: start, endDate: end)
                store.context.insert(challenge)
                store.context.insert(event)
                ChallengeTimeStore.setMembers([challenge.id], for: event.id)
                ChallengeTimeStore.setActualMinutes(20, for: challenge.id)
                let completion = ChallengeCompletion(challengeID: challenge.id, date: date(2026, 3, 2, 15), earnedCoins: 0)
                ChallengeTimeService.resize(context: store.context, completions: [completion])
                #expect(event.startDate == start)
                #expect(event.endDate == end)
            }
        }

        @Test func twoChallengesFormTheEventGroup() async throws {
            try await withTestStore { store in
                let start = date(2026, 3, 2, 10)
                let event = ChallengeCalendarEvent(title: "Termin", startDate: start, endDate: start.addingTimeInterval(3_600))
                let first = ChallengeItem(title: "A", startDate: start)
                let second = ChallengeItem(title: "B", startDate: start)
                store.context.insert(event)
                store.context.insert(first)
                store.context.insert(second)
                #expect(EventGroupSync.join(event: event, challengeIDs: [first.id], context: store.context) == nil)
                let groupID = try #require(EventGroupSync.join(event: event, challengeIDs: [first.id, second.id], context: store.context))
                let group = try #require(try store.all(ChallengeGroup.self).first { $0.id == groupID })
                #expect(group.title == EventGroupName.title(event: "Termin", day: AppDate.numeric(start)))
                #expect(first.groupIDs.contains(groupID))
                #expect(second.groupIDs.contains(groupID))
            }
        }

        @Test func aChallengeSitsOnOneEventOnly() async throws {
            try await withTestStore { _ in
                let challenge = UUID()
                let firstEvent = UUID()
                let secondEvent = UUID()
                ChallengeTimeStore.setMembers([challenge], for: firstEvent)
                ChallengeTimeStore.setMembers([challenge], for: secondEvent)
                #expect(ChallengeTimeStore.memberIDs(for: firstEvent).isEmpty)
                #expect(ChallengeTimeStore.memberIDs(for: secondEvent) == [challenge])
            }
        }
    }

    @Suite("Workout links")
    @MainActor
    struct WorkoutLinkTests {
        @Test func linksAreManyToMany() async throws {
            try await withTestStore { _ in
                let planA = UUID()
                let planB = UUID()
                let challenge = UUID()
                let otherChallenge = UUID()
                WorkoutLinkStore.link(planID: planA, challengeID: challenge)
                WorkoutLinkStore.link(planID: planB, challengeID: challenge)
                WorkoutLinkStore.link(planID: planA, challengeID: otherChallenge)
                #expect(Set(WorkoutLinkStore.planIDs(forChallenge: challenge)) == [planA, planB])
                #expect(Set(WorkoutLinkStore.challengeIDs(for: planA)) == [challenge, otherChallenge])
            }
        }

        @Test func linkingAChallengeAlsoLinksItsEvents() {
            let challenge = UUID()
            let event = UUID()
            let closed = WorkoutLinkRules.close(
                challenges: [challenge],
                events: [],
                calendar: [.init(eventID: event, challengeID: challenge)]
            )
            #expect(closed.events == [event])
        }

        @Test func trainingTimeRoundsToFiveMinutes() {
            #expect(WorkoutCalendarSync.duration(seconds: 0) == 300)
            #expect(WorkoutCalendarSync.duration(seconds: 449) == 300)
            #expect(WorkoutCalendarSync.duration(seconds: 450) == 600)
            #expect(WorkoutCalendarSync.clock(date(2026, 3, 2, 12, 2)) == date(2026, 3, 2, 12, 0))
            #expect(WorkoutCalendarSync.clock(date(2026, 3, 2, 12, 3)) == date(2026, 3, 2, 12, 5))
        }

        @Test func pastEventWithoutWorkoutIsRemoved() async throws {
            try await withTestStore { store in
                let plan = WorkoutPlan(name: "Push")
                let yesterday = days(-1, after: .now)
                let challenge = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: days(-7, after: .now))
                let missed = ChallengeCalendarEvent(title: "Sport", startDate: yesterday, endDate: yesterday.addingTimeInterval(3_600), linkedChallengeID: challenge.id)
                let unrelated = ChallengeCalendarEvent(title: "Zahnarzt", startDate: yesterday, endDate: yesterday.addingTimeInterval(3_600))
                let upcoming = days(1, after: .now)
                let future = ChallengeCalendarEvent(title: "Sport", startDate: upcoming, endDate: upcoming.addingTimeInterval(3_600), linkedChallengeID: challenge.id)
                [missed, unrelated, future].forEach(store.context.insert)
                store.context.insert(challenge)
                WorkoutLinkStore.link(planID: plan.id, challengeID: challenge.id)
                await WorkoutCalendarSync.cleanup(context: store.context, sessions: [])
                let titles = try store.all(ChallengeCalendarEvent.self).map(\.id)
                #expect(Set(titles) == [unrelated.id, future.id])
            }
        }

        @Test func anyLinkedWorkoutKeepsThePastEvent() async throws {
            try await withTestStore { store in
                let planA = WorkoutPlan(name: "Push")
                let planB = WorkoutPlan(name: "Pull")
                let yesterday = days(-1, after: .now)
                let challenge = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: days(-7, after: .now))
                let event = ChallengeCalendarEvent(title: "Sport", startDate: yesterday, endDate: yesterday.addingTimeInterval(3_600), linkedChallengeID: challenge.id)
                store.context.insert(challenge)
                store.context.insert(event)
                WorkoutLinkStore.link(planID: planA.id, challengeID: challenge.id)
                WorkoutLinkStore.link(planID: planB.id, challengeID: challenge.id)
                await WorkoutCalendarSync.cleanup(context: store.context, sessions: [WorkoutSession(plan: planB, now: yesterday)])
                try #expect(store.all(ChallengeCalendarEvent.self).count == 1)
            }
        }
    }
}
