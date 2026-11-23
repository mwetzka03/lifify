import Foundation
import LififyCore
import LififyFinance
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Dividends are summed from income bookings and forecast per share.
    @Suite("Dividend report")
    @MainActor
    struct DividendReportTests {
        private let now = date(2026, 6, 15)

        /// Inserts a holding with one bought lot.
        private func holding(_ store: TestStore, _ name: String, isin: String, shares: Double) -> PortfolioHolding {
            let holding = PortfolioHolding(name: name, symbol: isin, quantity: shares, purchasePriceCents: 1_000, currentPriceCents: 1_000)
            store.context.insert(holding)
            HoldingLotStore.replace([HoldingLot(
                date: date(2024, 1, 2), quantity: shares, unitPriceCents: 1_000, amountCents: Int(shares) * 1_000,
                isSale: false, isSavingsPlan: false
            )], holdingID: holding.id)
            return holding
        }

        /// Inserts a dividend booking.
        private func dividend(_ store: TestStore, _ day: Date, _ title: String, _ cents: Int) {
            store.context.insert(LedgerEntry(date: day, title: title, notes: "Typ: Ertrag", amountCents: cents, kind: .income))
        }

        @Test func sumsByPositionMonthAndYear() async throws {
            try await withTestStore { store in
                let apple = holding(store, "Apple", isin: "US0378331005", shares: 10)
                dividend(store, date(2025, 2, 10), "Apple", 100)
                dividend(store, date(2026, 2, 10), "Apple", 120)
                dividend(store, date(2026, 2, 20), "Altfonds", 50)
                store.context.insert(LedgerEntry(date: date(2026, 3, 1), title: "Gehalt", amountCents: 9_000, kind: .income))
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [apple], now: now)
                #expect(report.totalCents == 270)
                #expect(report.positions.map(\.name) == ["Apple", "Altfonds"])
                #expect(report.positions[0].lastYearCents == 120)
                #expect(report.months.map(\.id) == ["2026-02", "2025-02"])
                #expect(report.months[0].cents == 170)
                #expect(report.years.map(\.cents) == [170, 100])
            }
        }

        @Test func theForecastRepeatsLastYearsMonths() async throws {
            try await withTestStore { store in
                let apple = holding(store, "Apple", isin: "US0378331005", shares: 10)
                dividend(store, date(2025, 3, 10), "Apple", 999)
                dividend(store, date(2025, 8, 10), "Apple", 100)
                dividend(store, date(2026, 2, 10), "Apple", 120)
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [apple], now: now)
                #expect(report.forecastMonths.map(\.id) == ["2026-08", "2027-02"])
                #expect(report.forecastCents == 220)
            }
        }

        @Test func theForecastUsesTodaysShares() async throws {
            try await withTestStore { store in
                let etf = holding(store, "World", isin: "IE00B4L5Y983", shares: 10)
                dividend(store, date(2026, 2, 10), "World", 100)
                HoldingLotStore.add(HoldingLot(
                    date: date(2026, 4, 1), quantity: 10, unitPriceCents: 1_000, amountCents: 10_000,
                    isSale: false, isSavingsPlan: false
                ), holdingID: etf.id)
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [etf], now: now)
                #expect(report.forecastCents == 200)
            }
        }

        @Test func theForecastIncludesFutureSavingsPlanShares() async throws {
            try await withTestStore { store in
                let etf = holding(store, "World", isin: "IE00B4L5Y983", shares: 10)
                dividend(store, date(2026, 2, 10), "World", 100)
                FinanceClock.fix(now)
                defer { FinanceClock.fix(nil) }
                SavingsPlanStore.upsert(SavingsPlanRecord(
                    id: UUID(), isin: etf.symbol, name: etf.name, amountCents: 1_000, cadenceRaw: Cadence.monthly.rawValue,
                    checkingAccountID: UUID(), portfolioAccountID: UUID(), holdingID: etf.id,
                    lastExecution: now, historyThrough: now, active: true
                ))
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [etf], now: now)
                #expect(report.forecastCents > 100)
            }
        }

        @Test func accumulatingFundsDoNotAppear() async throws {
            try await withTestStore { store in
                let etf = holding(store, "Thesaurierer", isin: "IE00B4L5Y983", shares: 10)
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [etf], now: now)
                #expect(report.positions.isEmpty)
                #expect(report.forecastMonths.isEmpty)
            }
        }

        @Test func aSoldPositionHasNoForecast() async throws {
            try await withTestStore { store in
                dividend(store, date(2026, 2, 10), "Verkauft", 100)
                let report = try DividendReportBuilder.make(entries: store.all(), holdings: [], now: now)
                #expect(report.totalCents == 100)
                #expect(report.forecastCents == 0)
            }
        }
    }
}
