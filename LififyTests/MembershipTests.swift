import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// These pin down how the event links behave today. The links have different meanings.
    @Suite("Group and event membership")
    @MainActor
    struct MembershipTests {
        private let start = date(2026, 3, 2)

        @Test func groupListKeepsTheFirstGroupInStep() {
            let first = UUID(), second = UUID()
            let challenge = ChallengeItem(title: "A", groupID: first)
            #expect(challenge.groupIDs == [first])
            challenge.groupIDs = [second, first, second]
            #expect(challenge.groupIDs == [second, first])
            #expect(challenge.groupID == second)
            challenge.groupIDs = []
            #expect(challenge.groupID == nil)
            #expect(challenge.groupIDsRaw.isEmpty)
        }

        @Test func olderRecordWithOnlyOneGroupIsNormalized() async throws {
            try await withTestStore { store in
                let group = UUID()
                let challenge = ChallengeItem(title: "A", groupID: group)
                challenge.groupIDsRaw = ""
                store.context.insert(challenge)
                try store.context.save()
                LegacyDataMigration.run()
                let stored = try #require(LififyDatabase.sideContext?.fetch(FetchDescriptor<ChallengeItem>()).first)
                #expect(stored.groupIDsRaw == group.uuidString)
                #expect(stored.groupIDs == [group])
            }
        }

        @Test func eventShowsItsMembersAndItsDirectLink() async throws {
            try await withTestStore { _ in
                let member = UUID(), direct = UUID(), eventID = UUID()
                ChallengeTimeStore.setMembers([member], for: eventID)
                #expect(ChallengeTimeStore.challengeIDs(on: eventID, legacy: direct) == [member, direct])
                #expect(ChallengeTimeStore.challengeIDs(on: eventID, legacy: member) == [member])
            }
        }

        @Test func linkedEventsCoverDirectLinksAndMembers() async throws {
            try await withTestStore { _ in
                let challenge = UUID()
                let direct = ChallengeCalendarEvent(title: "Direkt", startDate: start, endDate: start, linkedChallengeID: challenge)
                let member = ChallengeCalendarEvent(title: "Mitglied", startDate: start, endDate: start)
                let other = ChallengeCalendarEvent(title: "Anders", startDate: start, endDate: start)
                ChallengeTimeStore.setMembers([challenge], for: member.id)
                let linked = ChallengeTimeStore.linkedEvents(for: challenge, in: [direct, member, other])
                #expect(Set(linked.map(\.id)) == [direct.id, member.id])
            }
        }

        /// The reason the direct link and the member list are not merged: only the direct link sets the streak quota.
        @Test func onlyTheDirectLinkDrivesTheStreakQuota() async throws {
            try await withTestStore { _ in
                let state = StreakSettings.State(enabled: true, enabledAt: start, purchased: 0, usedPeriodKeys: [])
                let challenge = ChallengeItem(title: "Woche", recurrence: .weekly, startDate: start, weeklyDays: [2, 4, 6])
                let event = ChallengeCalendarEvent(title: "T", startDate: start, endDate: start.addingTimeInterval(3_600))
                ChallengeTimeStore.setMembers([challenge.id], for: event.id)
                let asMember = ChallengeService.status(for: challenge, endingOn: start, completions: [], events: [event], streakState: state, usesStoredState: false)
                #expect(asMember.required == 3)
                event.linkedChallengeID = challenge.id
                let direct = ChallengeService.status(for: challenge, endingOn: start, completions: [], events: [event], streakState: state, usesStoredState: false)
                #expect(direct.required == 1)
            }
        }

        @Test func groupEventDrivesTheQuotaOfItsMembers() async throws {
            try await withTestStore { _ in
                let state = StreakSettings.State(enabled: true, enabledAt: start, purchased: 0, usedPeriodKeys: [])
                let group = UUID()
                let challenge = ChallengeItem(title: "Woche", recurrence: .weekly, startDate: start, weeklyDays: [2, 4, 6], groupID: group)
                let event = ChallengeCalendarEvent(title: "T", startDate: start, endDate: start.addingTimeInterval(3_600), linkedChallengeGroupID: group)
                let result = ChallengeService.status(for: challenge, endingOn: start, completions: [], events: [event], streakState: state, usesStoredState: false)
                #expect(result.required == 1)
            }
        }
    }

    @Suite("Backup coverage")
    @MainActor
    struct BackupCoverageTests {
        /// A new model must be added here together with its backup record.
        private let covered: Set<String> = [
            "Account", "LedgerEntry", "TransactionSplit", "FixedCost", "VariableBudget", "BudgetPool", "IncomeForecast",
            "ShoppingItem", "DebtEntry", "ExpenseGroup", "ExpenseGroupLine", "PortfolioHolding",
            "ChallengeCalendarEvent", "ChallengeItem", "ChallengeCompletion", "ChallengeGroup", "CoinTransaction",
            "RewardItem", "RewardPurchase", "BucketListItem",
            "StoredHoldingLot", "StoredSavingsPlan", "StoredClosedPosition", "StoredHoldingMarket", "StoredPortfolioLink",
            "StoredLink", "StoredTransferForecast", "StoredNoticeTemplate", "StoredStreakState", "StoredWorkoutLink", "StoredMeal"
        ]
        private let notBackedUp: Set<String> = ["DataMigrationRecord", "SavedArticle"]

        @Test func everyModelIsCoveredOrExcludedOnPurpose() {
            let models = Set(LififySchemaV3.models.map { String(describing: $0) })
            #expect(models == covered.union(notBackedUp))
        }

        @Test func everyLinkKindHasABackupPath() {
            let ownRecords: Set<LinkKind> = [
                .expenseGroup, .incomePrimary, .incomeSecondary, .incomeEntry, .challengeDuration, .challengeActual,
                .challengeMembers, .challengePlanned, .abstinenceDifficulty, .abstinenceAwarded, .abstinenceRelapses,
                .abstinenceNotices, .abstinenceExceptions, .abstinenceRewardLink, .rewardPolicy, .reminderSync,
                .reminderRecurrence, .eventRecurrence, .icon, .customCategories
            ]
            let carried = ownRecords.union(LinkKind.financeRecords).union(LinkKind.challengeRecords)
            #expect(carried == Set(LinkKind.allCases))
        }
    }
}
