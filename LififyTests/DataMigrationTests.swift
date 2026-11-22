import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Data migration")
    @MainActor
    struct DataMigrationTests {
        private let day = Date(timeIntervalSince1970: 1_780_000_000)

        private func seedDepot(_ defaults: UserDefaults) throws -> (holding: UUID, lots: [HoldingLot], plan: SavingsPlanRecord) {
            let holding = UUID()
            let lots = [
                HoldingLot(date: day, quantity: 2, unitPriceCents: 500, amountCents: -1_000, isSale: false, isSavingsPlan: true, ledgerEntryID: UUID()),
                HoldingLot(date: day.addingTimeInterval(60), quantity: 1, unitPriceCents: 700, amountCents: 700, isSale: true, isSavingsPlan: false, source: "cashback")
            ]
            let plan = SavingsPlanRecord(
                id: UUID(), isin: "IE00B4L5Y983", name: "World", amountCents: 2_500, cadenceRaw: "monthly",
                checkingAccountID: UUID(), portfolioAccountID: UUID(), holdingID: holding,
                lastExecution: day, historyThrough: day, active: true, fixedCostID: UUID()
            )
            let closed = ClosedPositionRecord(isin: "US0378331005", name: "Apple", lots: lots)
            defaults.set(try JSONEncoder().encode([holding.uuidString: lots]), forKey: "lifify.holdingLots")
            defaults.set(try JSONEncoder().encode([plan]), forKey: "lifify.savingsPlans")
            defaults.set(try JSONEncoder().encode([closed]), forKey: "lifify.closedPositions")
            defaults.set("AAPL", forKey: "market.symbol.\(holding.uuidString)")
            defaults.set(1_234, forKey: "market.previous.\(holding.uuidString)")
            defaults.set(day, forKey: "holding.purchased.\(holding.uuidString)")
            defaults.set(plan.portfolioAccountID.uuidString, forKey: "lifify.portfolioLink.\(plan.checkingAccountID.uuidString)")
            return (holding, lots, plan)
        }

        @Test func depotMovesCompletelyAndRemovesOldKeys() async throws {
            try await withTestStore { store in
                let seeded = try seedDepot(store.defaults)
                LegacyDataMigration.run()

                #expect(HoldingLotStore.lots(for: seeded.holding) == seeded.lots)
                #expect(SavingsPlanStore.all() == [seeded.plan])
                #expect(ClosedPositionStore.all().first?.lots == seeded.lots)
                #expect(MarketSymbolStore.symbol(for: seeded.holding) == "AAPL")
                #expect(PreviousCloseStore.cents(for: seeded.holding) == 1_234)
                #expect(HoldingPurchaseDateStore.date(for: seeded.holding) == day)
                #expect(PortfolioLinkStore.portfolioID(for: seeded.plan.checkingAccountID) == seeded.plan.portfolioAccountID)
                for key in ["lifify.holdingLots", "lifify.savingsPlans", "lifify.closedPositions", "market.symbol.\(seeded.holding.uuidString)"] {
                    #expect(store.defaults.object(forKey: key) == nil)
                }
            }
        }

        @Test func runningTwiceAddsNothing() async throws {
            try await withTestStore { store in
                let seeded = try seedDepot(store.defaults)
                LegacyDataMigration.run()
                LegacyDataMigration.run()
                #expect(HoldingLotStore.lots(for: seeded.holding).count == 2)
                try #expect(store.context.fetchCount(FetchDescriptor<StoredHoldingLot>()) == 2)
                try #expect(store.context.fetchCount(FetchDescriptor<StoredSavingsPlan>()) == 1)
            }
        }

        @Test func unreadableDataKeepsTheOldKeys() async throws {
            try await withTestStore { store in
                let seeded = try seedDepot(store.defaults)
                let broken = Data("not json".utf8)
                store.defaults.set(broken, forKey: "lifify.savingsPlans")
                LegacyDataMigration.run()
                #expect(store.defaults.data(forKey: "lifify.savingsPlans") == broken)
                #expect(store.defaults.data(forKey: "lifify.holdingLots") != nil)
                try #expect(store.context.fetchCount(FetchDescriptor<StoredHoldingLot>()) == 0)
                #expect(HoldingLotStore.lots(for: seeded.holding).isEmpty)
                #expect(!LegacyDataMigration.isFinished("depot", context: try #require(LififyDatabase.sideContext)))
            }
        }

        @Test func interruptedCleanupFinishesOnTheNextRun() async throws {
            try await withTestStore { store in
                let seeded = try seedDepot(store.defaults)
                let leftover = try #require(store.defaults.data(forKey: "lifify.holdingLots"))
                LegacyDataMigration.run()
                store.defaults.set(leftover, forKey: "lifify.holdingLots")
                LegacyDataMigration.run()
                #expect(store.defaults.object(forKey: "lifify.holdingLots") == nil)
                #expect(HoldingLotStore.lots(for: seeded.holding).count == 2)
            }
        }

        @Test func duplicateLotIDsSurvive() async throws {
            try await withTestStore { store in
                let holding = UUID()
                let lot = HoldingLot(date: day, quantity: 1, unitPriceCents: 1, amountCents: -1, isSale: false, isSavingsPlan: false)
                store.defaults.set(try JSONEncoder().encode([holding.uuidString: [lot, lot]]), forKey: "lifify.holdingLots")
                LegacyDataMigration.run()
                #expect(HoldingLotStore.lots(for: holding) == [lot, lot])
            }
        }

        @Test func financeLinksMoveCompletely() async throws {
            try await withTestStore { store in
                let defaults = store.defaults
                let refund = UUID(), original = UUID(), forecast = UUID(), entry = UUID(), group = UUID(), budget = UUID(), account = UUID()
                let transfer = TransferForecastRecord(name: "Sparen", amountCents: 5_000, fromAccountID: account, cadence: .weekly, firstDate: day, dueRule: .lastBusinessDay, dayOfMonth: 3)
                let template = NoticeTemplate(id: UUID(), accountID: account, name: "Steam", example: "Steam -9,99", action: .expense)
                defaults.set([refund.uuidString: original.uuidString], forKey: "lifify.refundLinks")
                defaults.set([entry.uuidString: forecast.uuidString], forKey: "lifify.transferForecastAssignments")
                defaults.set([entry.uuidString: "fixed|\(forecast.uuidString)"], forKey: "lifify.forecastPeriodLinks")
                defaults.set([entry.uuidString: group.uuidString], forKey: "lifify.expenseGroupAssignments")
                defaults.set(["DE1": forecast.uuidString], forKey: "secondaryIncomeMappings")
                defaults.set([entry.uuidString: forecast.uuidString], forKey: "incomeEntryAssignments")
                defaults.set("DE2", forKey: "primaryIncomeIBAN")
                defaults.set(forecast.uuidString, forKey: "primaryIncomeForecastID")
                defaults.set(["income|\(forecast.uuidString)|\(day.dayKey)"], forKey: "lifify.forecastSkips")
                defaults.set(["fixed|\(forecast.uuidString)|\(entry.uuidString)"], forKey: "lifify.forecastMatchRejections")
                defaults.set(try JSONEncoder().encode([transfer]), forKey: "lifify.transferForecasts")
                defaults.set(try JSONEncoder().encode([template]), forKey: "lifify.noticeTemplates")
                defaults.set(try JSONEncoder().encode([budget.uuidString: [account]]), forKey: "lifify.variableBudgetAccounts")
                defaults.set(1_780_000_000.5, forKey: "lifify.bankImport.cursor.\(account.uuidString)")
                defaults.set(-1_234, forKey: "lifify.bankImport.current.\(account.uuidString)")

                LegacyDataMigration.run()

                #expect(RefundLinkStore.originalID(for: refund) == original)
                #expect(TransferForecastAssignmentStore.forecastID(for: entry) == forecast)
                #expect(ForecastPeriodLinkStore.link(for: entry)?.id == forecast)
                #expect(ExpenseGroupAssignmentStore.groupID(for: entry) == group)
                #expect(IncomeAssignmentStore.forecastID(for: "DE1") == forecast)
                #expect(IncomeAssignmentStore.forecastID(for: "DE2") == forecast)
                #expect(IncomeAssignmentStore.primaryForecastID == forecast)
                #expect(IncomeAssignmentStore.forecastID(forEntryID: entry) == forecast)
                #expect(ForecastSkipStore.isSkipped(.income, id: forecast, on: day))
                #expect(ForecastMatchRejectionStore.isRejected(costID: forecast, entryID: entry))
                #expect(TransferForecastStore.all() == [transfer])
                #expect(NoticeTemplateStore.all() == [template])
                #expect(VariableBudgetAccounts.storedIDs(for: budget) == [account])
                #expect(BankImportCursor.date(for: account) == Date(timeIntervalSince1970: 1_780_000_000.5))
                #expect(BankImportCursor.currentCents(for: account) == -1_234)
                for key in ["lifify.refundLinks", "primaryIncomeForecastID", "lifify.forecastSkips", "lifify.transferForecasts", "lifify.bankImport.cursor.\(account.uuidString)"] {
                    #expect(defaults.object(forKey: key) == nil)
                }
            }
        }

        @Test func financeLinksSurviveBackupAndRestore() async throws {
            try await withTestStore { store in
                let refund = UUID(), original = UUID(), forecast = UUID(), budget = UUID(), account = UUID()
                let transfer = TransferForecastRecord(name: "Sparen", amountCents: 5_000, firstDate: day)
                let template = NoticeTemplate(id: UUID(), accountID: account, name: "Steam", example: "Steam -9,99", action: .expense)
                RefundLinkStore.link(refundID: refund, to: original)
                ForecastSkipStore.skip(.income, id: forecast, on: day)
                TransferForecastStore.upsert(transfer)
                NoticeTemplateStore.save([template])
                VariableBudgetAccounts.set([account], for: budget)
                BankImportCursor.mark(account, at: day, currentCents: 500)
                let data = try BackupService.exportData(
                    accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .finance
                )
                try BackupService.deleteFinanceData(from: store.context)
                VariableBudgetAccounts.reset()
                #expect(TransferForecastStore.all().isEmpty)
                try BackupService.restore(data: data, into: store.context)
                AppDefaults.clearCaches()
                #expect(RefundLinkStore.originalID(for: refund) == original)
                #expect(ForecastSkipStore.isSkipped(.income, id: forecast, on: day))
                #expect(TransferForecastStore.all() == [transfer])
                #expect(NoticeTemplateStore.all() == [template])
                #expect(VariableBudgetAccounts.storedIDs(for: budget) == [account])
                #expect(BankImportCursor.date(for: account) == day)
                #expect(BankImportCursor.currentCents(for: account) == 500)
            }
        }

        @Test func challengeDataMovesCompletely() async throws {
            try await withTestStore { store in
                let d = store.defaults
                let challenge = UUID(), event = UUID(), plan = UUID(), reward = UUID(), group = UUID()
                let state = StreakSettings.State(enabled: true, enabledAt: day, purchased: 2, usedPeriodKeys: ["d:2026-03-03"])
                let relapse = AbstinenceRelapse(id: UUID(), date: day, lasted: 90)
                let exception = AbstinenceException(id: UUID(), date: day, rewardID: reward, rewardTitle: "Kino")
                let notice = AbstinenceNotice(id: "n", challengeID: challenge, title: "T", milestone: "1h", coins: 3, date: day)
                let category = CustomChallengeCategory(id: UUID(), name: "Lernen", separate: true)
                let recurrence = ReminderRecurrenceMetadata(recurrence: .weekly, interval: 2, weekdays: [2, 4], endDate: day)
                let meal = MealRecord(dayKey: "2026-03-02", title: "Reis", note: "n", createdAt: day, source: .photo, status: .confirmed, photoName: "a.jpg", nutrients: ["calories": 512.5], kind: .fastFood, chargeID: UUID())
                d.set(try JSONEncoder().encode([challenge.uuidString: state]), forKey: "lifify.streakStates")
                d.set(try JSONEncoder().encode([challenge.uuidString: 45]), forKey: "lifify.challengeDuration")
                d.set(try JSONEncoder().encode([challenge.uuidString: 30]), forKey: "lifify.challengeActualMinutes")
                d.set(try JSONEncoder().encode([event.uuidString: [challenge.uuidString]]), forKey: "lifify.challengeTimeMembers")
                d.set(try JSONEncoder().encode([event.uuidString: 60]), forKey: "lifify.challengeTimePlanned")
                d.set(try JSONEncoder().encode([challenge.uuidString: "hard"]), forKey: "lifify.abstinenceDifficulty")
                d.set(try JSONEncoder().encode([challenge.uuidString: ["1h"]]), forKey: "lifify.abstinenceAwarded")
                d.set(try JSONEncoder().encode([challenge.uuidString: [relapse]]), forKey: "lifify.abstinenceRelapses")
                d.set(try JSONEncoder().encode([notice]), forKey: "lifify.abstinenceNotices")
                d.set(try JSONEncoder().encode([challenge.uuidString: [exception]]), forKey: "lifify.abstinenceExceptions")
                d.set(try JSONEncoder().encode([reward.uuidString: challenge.uuidString]), forKey: "lifify.abstinenceRewardLinks")
                d.set(try JSONEncoder().encode([category]), forKey: "lifify.customCategories")
                d.set([challenge.uuidString], forKey: "lifify.pinnedChallenges")
                d.set([group.uuidString], forKey: "lifify.pinnedChallengeGroups")
                d.set(try JSONEncoder().encode([WorkoutChallengeLink(planID: plan, challengeID: challenge)]), forKey: "lifify.workoutChallengeLinks")
                d.set(try JSONEncoder().encode([WorkoutEventLink(planID: plan, eventID: event, managed: true)]), forKey: "lifify.workoutEventLinks")
                d.set(try JSONEncoder().encode([meal]), forKey: "lifify.meals")
                d.set(reward.uuidString, forKey: "lifify.fastFoodReward")
                d.set(false, forKey: "reward.multiple.\(reward.uuidString)")
                d.set(false, forKey: "challenge.syncReminders.\(challenge.uuidString)")
                d.set(false, forKey: "lifify.eventOffer.\(challenge.uuidString)")
                d.set(try JSONEncoder().encode(recurrence), forKey: "reminder.recurrence.ext")
                d.set(try JSONEncoder().encode(recurrence), forKey: "event.recurrence.cal")
                d.set("star", forKey: "icon.\(challenge.uuidString)")

                LegacyDataMigration.run()

                #expect(StreakSettings.state(for: challenge) == state)
                #expect(ChallengeTimeStore.minutes(for: challenge) == 45)
                #expect(ChallengeTimeStore.actualMinutes(for: challenge) == 30)
                #expect(ChallengeTimeStore.memberIDs(for: event) == [challenge])
                #expect(ChallengeTimeStore.plannedMinutes(for: event) == 60)
                #expect(AbstinenceSettings.difficulty(for: challenge) == .hard)
                #expect(AbstinenceSettings.awarded(for: challenge) == ["1h"])
                #expect(AbstinenceSettings.relapses(for: challenge) == [relapse])
                #expect(AbstinenceSettings.notices() == [notice])
                #expect(AbstinenceSettings.exceptions(for: challenge) == [exception])
                #expect(AbstinenceSettings.rewardLink(for: reward) == challenge)
                #expect(ChallengeCategoryStore.all() == [category])
                #expect(ChallengePinStore.ids() == [challenge])
                #expect(ChallengeGroupPinStore.ids() == [group])
                #expect(WorkoutLinkStore.planIDs(forChallenge: challenge) == [plan])
                #expect(WorkoutLinkStore.isManaged(eventID: event))
                #expect(MealLog.all() == [meal])
                #expect(!RewardPolicyStore.allowsMultiplePurchases(for: reward))
                #expect(!ReminderSyncPreference.isEnabled(for: challenge))
                #expect(!EventOffer.isEnabled(for: challenge))
                #expect(ReminderLinkStore.metadata(for: "ext")?.interval == 2)
                #expect(EventRecurrenceStore.metadata(for: "cal")?.weekdays == [2, 4])
                #expect(IconPreferenceStore.storedIcon(for: challenge) == "star")
                for key in ["lifify.streakStates", "lifify.meals", "lifify.pinnedChallenges", "reminder.recurrence.ext", "icon.\(challenge.uuidString)"] {
                    #expect(d.object(forKey: key) == nil)
                }
            }
        }

        @Test func valuesSurviveAFreshRead() async throws {
            try await withTestStore { _ in
                let holding = UUID()
                let lot = HoldingLot(date: day, quantity: 3, unitPriceCents: 10, amountCents: -30, isSale: false, isSavingsPlan: false)
                HoldingLotStore.add(lot, holdingID: holding)
                MarketSymbolStore.set("MSFT", for: holding)
                PreviousCloseStore.set(99, for: holding)
                MarketSymbolStore.remove(for: holding)
                AppDefaults.clearCaches()
                #expect(HoldingLotStore.lots(for: holding) == [lot])
                #expect(MarketSymbolStore.symbol(for: holding) == nil)
                #expect(PreviousCloseStore.cents(for: holding) == 99)
            }
        }
    }
}
