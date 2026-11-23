import Foundation
import LififyChallenges
import LififyCore
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Covers the paths that change or delete real calendar data, through a recording gateway.
    @Suite("Calendar paths")
    @MainActor
    struct CalendarPathTests {
        /// A given hour of the current day, so cleanup does not treat it as a past day.
        private func today(_ hour: Int, _ minute: Int = 0) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
        }

        /// A finished session from 10:00 to 11:03 today.
        private func finishedSession(planID: UUID = UUID()) -> WorkoutSession {
            var session = WorkoutSession(plan: WorkoutPlan(id: planID, name: "Push"), now: today(10))
            session.finishedAt = today(11, 3)
            return session
        }

        /// Exports everything in the store as a full backup.
        private func fullBackup(_ store: TestStore) throws -> Data {
            try BackupService.exportData(
                accounts: store.all(), entries: store.all(), splits: store.all(), fixedCosts: store.all(),
                variableBudgets: store.all(), pools: store.all(), forecasts: store.all(), shopping: store.all(),
                debts: store.all(), groups: store.all(), lines: store.all(), holdings: store.all(),
                calendarEvents: store.all(), challenges: store.all(), completions: store.all(),
                challengeGroups: store.all(), coinTransactions: store.all(), rewards: store.all(),
                purchases: store.all(), bucketItems: store.all(), scope: .all
            )
        }

        @Test func finishedEventIsDeletedAndCreatedAgain() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let start = date(2026, 3, 2, 10)
                let challenge = ChallengeItem(title: "Lesen", startDate: start)
                let event = ChallengeCalendarEvent(
                    title: "Termin", startDate: start, endDate: date(2026, 3, 2, 11), externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                ChallengeTimeStore.setMembers([challenge.id], for: event.id)
                ChallengeTimeStore.setActualMinutes(20, for: challenge.id)
                let checkedOff = date(2026, 3, 2, 15)
                let completion = ChallengeCompletion(challengeID: challenge.id, date: checkedOff, earnedCoins: 0)

                await ChallengeTimeService.resize(context: store.context, completions: [completion])?.value

                #expect(store.calendar.deletions == [.init(identifier: "ios-1", occurrenceStart: start)])
                let saved = try #require(store.calendar.savedEvents.first)
                #expect(saved.externalIdentifier == nil)
                #expect(saved.start == checkedOff.addingTimeInterval(-20 * 60))
                #expect(saved.end == checkedOff)
                #expect(event.externalIdentifier == "system-1")
            }
        }

        @Test func resizeWithoutAccessStillMovesTheLocalEvent() async throws {
            try await withTestStore { store in
                let start = date(2026, 3, 2, 10)
                let challenge = ChallengeItem(title: "Lesen", startDate: start)
                let event = ChallengeCalendarEvent(
                    title: "Termin", startDate: start, endDate: date(2026, 3, 2, 11), externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                ChallengeTimeStore.setMembers([challenge.id], for: event.id)
                ChallengeTimeStore.setActualMinutes(20, for: challenge.id)
                let checkedOff = date(2026, 3, 2, 15)
                let completion = ChallengeCompletion(challengeID: challenge.id, date: checkedOff, earnedCoins: 0)

                await ChallengeTimeService.resize(context: store.context, completions: [completion])?.value

                #expect(event.endDate == checkedOff)
                #expect(event.externalIdentifier == nil)
                #expect(store.calendar.savedEvents.isEmpty)
            }
        }

        @Test func workoutMovesOnlyThatOccurrenceAndChecksOff() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let session = finishedSession()
                let challenge = ChallengeItem(
                    title: "Sport", category: .sport, recurrence: .daily, startDate: days(-3, after: today(9))
                )
                let event = ChallengeCalendarEvent(
                    title: "Sport", startDate: today(9), endDate: today(10),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                WorkoutLinkStore.link(planID: session.planID, challengeID: challenge.id)

                await WorkoutCalendarSync.apply(session: session, context: store.context, sessions: [session])

                let saved = try #require(store.calendar.savedEvents.first)
                #expect(saved.externalIdentifier == "ios-1")
                #expect(saved.originalStart == today(9))
                #expect(saved.occurrenceOnly)
                #expect(saved.start == today(10))
                #expect(saved.end == today(11, 5))
                #expect(event.startDate == today(10))
                try #expect(store.all(ChallengeCompletion.self).map(\.challengeID) == [challenge.id])
            }
        }

        @Test func workoutKeepsTheLocalTimeWhenCalendarRefuses() async throws {
            try await withTestStore { store in
                let session = finishedSession()
                let challenge = ChallengeItem(
                    title: "Sport", category: .sport, recurrence: .daily, startDate: days(-3, after: today(9))
                )
                let event = ChallengeCalendarEvent(
                    title: "Sport", startDate: today(9), endDate: today(10),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                WorkoutLinkStore.link(planID: session.planID, challengeID: challenge.id)

                await WorkoutCalendarSync.apply(session: session, context: store.context, sessions: [session])

                #expect(event.startDate == today(9))
                #expect(event.externalIdentifier == "ios-1")
            }
        }

        @Test func workoutWithoutEventCreatesAManagedOccurrence() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let session = finishedSession()
                let challenge = ChallengeItem(
                    title: "Sport", category: .sport, recurrence: .daily, startDate: days(-3, after: today(9))
                )
                store.context.insert(challenge)
                WorkoutLinkStore.link(planID: session.planID, challengeID: challenge.id)

                await WorkoutCalendarSync.apply(session: session, context: store.context, sessions: [session])

                let created = try #require(try store.all(ChallengeCalendarEvent.self).first)
                #expect(created.linkedChallengeID == challenge.id)
                #expect(created.externalIdentifier == "system-1")
                #expect(created.details.contains(WorkoutCalendarSync.noteMarker))
                #expect(WorkoutLinkStore.isManaged(eventID: created.id))
            }
        }

        @Test func cleanupDeletesAMissedPastOccurrence() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let past = days(-2, after: today(9))
                let planID = UUID()
                let challenge = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: past)
                let event = ChallengeCalendarEvent(
                    title: "Sport", startDate: past, endDate: past.addingTimeInterval(3_600),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                WorkoutLinkStore.link(planID: planID, challengeID: challenge.id)

                await WorkoutCalendarSync.cleanup(context: store.context, sessions: [])

                #expect(store.calendar.deletions == [.init(identifier: "ios-1", occurrenceStart: past)])
                try #expect(store.all(ChallengeCalendarEvent.self).isEmpty)
            }
        }

        @Test func cleanupKeepsCoveredTodayAndUnrelatedEvents() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let past = days(-2, after: today(9))
                let planID = UUID()
                var session = WorkoutSession(plan: WorkoutPlan(id: planID, name: "Push"), now: past)
                session.finishedAt = past.addingTimeInterval(1_800)
                let challenge = ChallengeItem(title: "Sport", category: .sport, recurrence: .daily, startDate: past)
                let covered = ChallengeCalendarEvent(
                    title: "Sport", startDate: past, endDate: past.addingTimeInterval(3_600),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-1"
                )
                let current = ChallengeCalendarEvent(
                    title: "Sport", startDate: today(9), endDate: today(10),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-2"
                )
                let unrelated = ChallengeCalendarEvent(
                    title: "Arzt", startDate: past, endDate: past.addingTimeInterval(3_600), externalIdentifier: "ios-3"
                )
                [covered, current, unrelated].forEach(store.context.insert)
                store.context.insert(challenge)
                WorkoutLinkStore.link(planID: planID, challengeID: challenge.id)

                await WorkoutCalendarSync.cleanup(context: store.context, sessions: [session])

                #expect(store.calendar.deletions.isEmpty)
                try #expect(store.all(ChallengeCalendarEvent.self).count == 3)
            }
        }

        @Test func abstinenceBonusPaysOnceAndAgainAfterARelapse() async throws {
            try await withTestStore { store in
                let start = date(2026, 3, 9, 11)
                let now = date(2026, 3, 10, 12)
                let challenge = ChallengeItem(title: "Rauchfrei", category: .abstinence, startDate: start, rewardCoins: 10)
                store.context.insert(challenge)

                AbstinenceService.settle(context: store.context, now: now)
                let paid = try store.wallet()
                #expect(paid > 0)
                #expect(AbstinenceSettings.awarded(for: challenge.id).contains(AbstinenceMilestone.hour24.rawValue))
                AbstinenceService.settle(context: store.context, now: now)
                try #expect(store.wallet() == paid)

                AbstinenceService.relapse(challenge, context: store.context, now: now)
                #expect(challenge.startDate == now)
                #expect(AbstinenceSettings.relapses(for: challenge.id).count == 1)
                #expect(AbstinenceSettings.awarded(for: challenge.id).isEmpty)
                try #expect(store.wallet() >= paid)

                AbstinenceService.settle(context: store.context, now: now.addingTimeInterval(2 * 3_600))
                #expect(AbstinenceSettings.awarded(for: challenge.id).contains(AbstinenceMilestone.hour1.rawValue))
            }
        }

        @Test func fullRestoreKeepsEventLinksAndLeavesTheCalendarAlone() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let start = date(2026, 3, 2, 10)
                let challenge = ChallengeItem(title: "Lesen", startDate: start)
                let event = ChallengeCalendarEvent(
                    title: "Termin", startDate: start, endDate: date(2026, 3, 2, 11),
                    linkedChallengeID: challenge.id, externalIdentifier: "ios-1"
                )
                store.context.insert(challenge)
                store.context.insert(event)
                try store.context.save()
                let data = try fullBackup(store)

                try BackupService.resetApp(from: store.context)
                try store.context.save()
                try BackupService.restore(data: data, into: store.context)
                try store.context.save()

                let restored = try #require(try store.all(ChallengeCalendarEvent.self).first)
                #expect(restored.id == event.id)
                #expect(restored.linkedChallengeID == challenge.id)
                #expect(restored.externalIdentifier == "ios-1")
                #expect(restored.startDate == start)
                #expect(store.calendar.savedEvents.isEmpty)
                #expect(store.calendar.deletions.isEmpty)
            }
        }

        @Test func healthRestoreLeavesTheCalendarAlone() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let workouts = WorkoutStore(fileURL: WorkoutStore.defaultFileURL())
                let plan = WorkoutPlan(name: "Push")
                workouts.save(plan: plan)
                let data = try BackupService.exportData(
                    accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .training,
                    workoutSnapshot: workouts.exportSnapshotData()
                )

                WorkoutStore.clearStored()
                try BackupService.restore(data: data, into: store.context)

                #expect(WorkoutStore(fileURL: WorkoutStore.defaultFileURL()).plans.map(\.id) == [plan.id])
                #expect(store.calendar.savedEvents.isEmpty)
                #expect(store.calendar.deletions.isEmpty)
            }
        }

        @Test func syncImportsEventsAndRemovesVanishedOnes() async throws {
            try await withTestStore { store in
                store.calendar.grantsAccess = true
                let vanished = ChallengeCalendarEvent(
                    title: "Weg", startDate: today(8), endDate: today(9), externalIdentifier: "ios-gone", isReadOnly: true
                )
                store.context.insert(vanished)
                try store.context.save()
                store.calendar.storedEvents = [CalendarEventSnapshot(
                    identifier: "ios-new", title: "Neu", notes: "Notiz",
                    startDate: today(12), endDate: today(13), isAllDay: false
                )]

                await EventKitSyncService().sync(
                    context: store.context,
                    existingEvents: [vanished],
                    existingChallenges: [],
                    promptForAccess: false
                )

                let events = try store.all(ChallengeCalendarEvent.self)
                #expect(events.map(\.externalIdentifier) == ["ios-new"])
                #expect(events.first?.details == "Notiz")
            }
        }
    }
}
