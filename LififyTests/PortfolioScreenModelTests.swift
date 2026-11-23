import Foundation
import LififyCore
import LififyFinance
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// The depot model must equal the direct calculation and never show an outdated result.
    @Suite("Portfolio screen model")
    @MainActor
    struct PortfolioScreenModelTests {
        /// Inserts one position with a single bought lot.
        private func holding(_ store: TestStore, _ name: String, price: Int) -> PortfolioHolding {
            let holding = PortfolioHolding(name: name, quantity: 2, purchasePriceCents: 1_000, currentPriceCents: price)
            store.context.insert(holding)
            HoldingLotStore.replace([HoldingLot(
                date: days(-5, after: .now), quantity: 2, unitPriceCents: 1_000, amountCents: 2_000,
                isSale: false, isSavingsPlan: false
            )], holdingID: holding.id)
            return holding
        }

        @Test func matchesTheDirectCalculationAndSorts() async throws {
            try await withTestStore { store in
                let small = holding(store, "A", price: 1_100)
                let large = holding(store, "B", price: 3_000)
                let holdings = [small, large]
                let model = PortfolioScreenModel()
                let result = model.snapshot(holdings: holdings, through: .now, sort: PortfolioSort.value.rawValue)
                #expect(result.rows.map(\.id) == [large.id, small.id])
                #expect(result.marketValueCents == HoldingMaintenance.marketValue(of: holdings, through: .now))
                #expect(result.rows[0].valueCents == 6_000)
                #expect(result.rows[0].shownPriceCents == 3_000)
                #expect(result.totals.purchaseCents == 4_200)
                let byName = model.snapshot(holdings: holdings, through: .now, sort: PortfolioSort.name.rawValue)
                #expect(byName.rows.map(\.id) == [small.id, large.id])
            }
        }

        @Test func repeatsWhenPriceLotOrPreviousCloseChanges() async throws {
            try await withTestStore { store in
                let position = holding(store, "A", price: 1_100)
                let model = PortfolioScreenModel()
                let sort = PortfolioSort.value.rawValue
                #expect(model.snapshot(holdings: [position], through: .now, sort: sort).totals.dayCents == nil)

                PreviousCloseStore.set(1_000, for: position.id)
                #expect(model.snapshot(holdings: [position], through: .now, sort: sort).totals.dayCents == 200)

                position.currentPriceCents = 1_200
                #expect(model.snapshot(holdings: [position], through: .now, sort: sort).rows[0].valueCents == 2_400)

                HoldingLotStore.add(HoldingLot(
                    date: days(-1, after: .now), quantity: 1, unitPriceCents: 1_000, amountCents: 1_000,
                    isSale: false, isSavingsPlan: false
                ), holdingID: position.id)
                #expect(model.snapshot(holdings: [position], through: .now, sort: sort).rows[0].quantity == 3)
            }
        }

        @Test func aSoldOutPositionLeavesTheRows() async throws {
            try await withTestStore { store in
                let position = holding(store, "A", price: 1_100)
                HoldingLotStore.add(HoldingLot(
                    date: days(-1, after: .now), quantity: 2, unitPriceCents: 1_100, amountCents: 2_200,
                    isSale: true, isSavingsPlan: false
                ), holdingID: position.id)
                let result = PortfolioScreenModel().snapshot(
                    holdings: [position], through: .now, sort: PortfolioSort.value.rawValue
                )
                #expect(result.rows.isEmpty)
            }
        }
    }
}
