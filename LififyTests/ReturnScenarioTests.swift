import Foundation
import LififyCore
import LififyFinance
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// ETFs grow only in future periods and only while the scenario is on.
    @Suite("Return scenario")
    @MainActor
    struct ReturnScenarioTests {
        private let now = date(2026, 3, 18)
        private let isin = "IE00B4L5Y983"

        /// Runs at the fixed time with a March period as the running one.
        private func fixed(_ body: (TestStore) async throws -> Void) async throws {
            FinanceClock.fix(now)
            defer { FinanceClock.fix(nil) }
            try await withTestStore { store in
                ReturnScenario.noteCurrentPeriod(in: [ForecastPeriod(start: date(2026, 3, 1), end: date(2026, 3, 31))], now: now)
                try await body(store)
            }
        }

        /// Inserts a position of ten shares at 100 euros.
        private func position(_ store: TestStore, symbol: String? = nil) -> PortfolioHolding {
            let holding = PortfolioHolding(name: "World", symbol: symbol ?? isin, quantity: 10, purchasePriceCents: 10_000, currentPriceCents: 10_000)
            store.context.insert(holding)
            HoldingLotStore.replace([HoldingLot(date: date(2025, 1, 2), quantity: 10, unitPriceCents: 10_000, amountCents: 100_000, isSale: false, isSavingsPlan: false)], holdingID: holding.id)
            return holding
        }

        /// Turns the scenario on with a known rate.
        private func enable(_ store: TestStore, annual: Double = 0.12, isETF: Bool = true) {
            store.defaults.set(true, forKey: ReturnScenario.enabledKey)
            ReturnScenario.store(ScenarioRate(annual: annual, basis: .tenYears, isETF: isETF), for: isin)
        }

        /// Monthly prices growing by a fixed yearly rate, ending at `now`.
        private func prices(years: Int, annual: Double) -> [(date: Date, price: Double)] {
            (0...(years * 12)).map { month in
                (Calendar.current.date(byAdding: .month, value: month - years * 12, to: now)!, 100 * pow(1 + annual, Double(month) / 12))
            }
        }

        @Test func offLeavesTheForecastUnchanged() async throws {
            try await fixed { store in
                let holding = position(store)
                ReturnScenario.store(ScenarioRate(annual: 0.12, basis: .tenYears, isETF: true), for: isin)
                #expect(HoldingMaintenance.marketValue(of: holding, through: date(2027, 3, 18), holdings: [holding]) == 100_000)
            }
        }

        @Test func anETFGrowsInAFuturePeriod() async throws {
            try await fixed { store in
                let holding = position(store)
                enable(store)
                #expect(HoldingMaintenance.marketValue(of: holding, through: date(2027, 3, 18), holdings: [holding]) == 112_000)
            }
        }

        @Test func theRunningPeriodAndThePastStayUnchanged() async throws {
            try await fixed { store in
                let holding = position(store)
                enable(store)
                #expect(HoldingMaintenance.marketValue(of: holding, through: date(2026, 3, 31), holdings: [holding]) == 100_000)
                #expect(HoldingMaintenance.marketValue(of: holding, through: date(2026, 2, 1), holdings: [holding]) == 100_000)
            }
        }

        @Test func aStockKeepsItsCurrentPrice() async throws {
            try await fixed { store in
                let holding = position(store)
                enable(store, isETF: false)
                #expect(HoldingMaintenance.marketValue(of: holding, through: date(2027, 3, 18), holdings: [holding]) == 100_000)
            }
        }

        @Test func aManualCorrectionWins() async throws {
            try await fixed { store in
                let holding = position(store)
                enable(store, isETF: false)
                ReturnScenario.setOverride(.etf, for: isin)
                #expect(ReturnScenario.isETF(holding))
                ReturnScenario.setOverride(.other, for: isin)
                #expect(!ReturnScenario.isETF(holding))
                ReturnScenario.setOverride(.automatic, for: isin)
                #expect(!ReturnScenario.isETF(holding))
            }
        }

        @Test func futureSavingsGrowOnlyFromTheirExecution() async throws {
            try await fixed { store in
                let holding = position(store)
                enable(store)
                SavingsPlanStore.upsert(SavingsPlanRecord(
                    id: UUID(), isin: isin, name: "World", amountCents: 10_000, cadenceRaw: Cadence.monthly.rawValue,
                    checkingAccountID: UUID(), portfolioAccountID: UUID(), holdingID: holding.id,
                    lastExecution: date(2026, 3, 2), historyThrough: date(2026, 3, 2), active: true
                ))
                let value = HoldingMaintenance.marketValue(of: holding, through: date(2027, 3, 18), holdings: [holding])
                let flat = 112_000 + 12 * 10_000
                #expect(value > flat)
                #expect(value < 112_000 + Int(12 * 10_000 * 1.12))
            }
        }

        @Test func growthCompoundsOverWholeMonths() {
            #expect(abs(ReturnScenario.growth(annual: 0.12, from: date(2026, 1, 1), to: date(2028, 1, 1)) - 1.2544) < 0.000001)
            #expect(ReturnScenario.growth(annual: 0.12, from: date(2026, 1, 1), to: date(2026, 1, 20)) == 1)
        }

        @Test func theBasisFollowsTheHistoryLength() {
            let ten = ReturnScenario.historicReturn(points: prices(years: 10, annual: 0.08), now: now)
            #expect(ten.basis == .tenYears)
            #expect(abs(ten.annual - 0.08) < 0.0005)
            let seven = ReturnScenario.historicReturn(points: prices(years: 7, annual: 0.06), now: now)
            #expect(seven.basis == .fiveYears)
            #expect(abs(seven.annual - 0.06) < 0.0005)
            let short = ReturnScenario.historicReturn(points: prices(years: 3, annual: 0.2), now: now)
            #expect(short.basis == .standard)
            #expect(short.annual == 0.03)
        }

        @Test func anETFWithoutARateUsesTheStandard() async throws {
            try await fixed { store in
                let holding = position(store, symbol: "IE00BK5BQT80")
                store.defaults.set(true, forKey: ReturnScenario.enabledKey)
                ReturnScenario.setOverride(.etf, for: holding.symbol)
                #expect(ReturnScenario.annualReturn(for: holding) == 0.03)
            }
        }
    }
}
