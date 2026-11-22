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
