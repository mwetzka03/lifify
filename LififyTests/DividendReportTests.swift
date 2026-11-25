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

        @Test func expectedDividendsCountAsIncomeOnlyWithTheSwitch() async throws {
            try await withTestStore { store in
                FinanceClock.fix(now)
                defer { FinanceClock.fix(nil) }
                let giro = Account(name: "Giro", isMain: true)
                let other = Account(name: "Tagesgeld")
                store.context.insert(giro)
                store.context.insert(other)
                let apple = holding(store, "Apple", isin: "US0378331005", shares: 10)
                let paid = LedgerEntry(date: date(2026, 2, 10), title: "Apple", notes: "Typ: Ertrag", amountCents: 120, kind: .income)
                paid.accountID = giro.id
                store.context.insert(paid)
                try store.context.save()
                let entries: [LedgerEntry] = try store.all()
                let february = ForecastPeriod(start: date(2027, 2, 1), end: date(2027, 2, 28))
                @MainActor func income(_ accounts: [Account]) -> Int {
                    FinanceService.periodForecast(
                        period: february, periods: [february], accounts: accounts, entries: entries, holdings: [apple],
                        fixedCosts: [], variableBudgets: [], splits: [], forecasts: [], shopping: [], now: now
                    ).income
                }
                #expect(income([giro]) == 0)
                store.defaults.set(true, forKey: DividendReportBuilder.incomeKey)
                #expect(income([giro]) == 120)
                #expect(income([other]) == 0)
                let lines = FinanceService.periodForecast(
                    period: february, periods: [february], accounts: [giro], entries: entries, holdings: [apple],
                    fixedCosts: [], variableBudgets: [], splits: [], forecasts: [], shopping: [], now: now
                ).events
                #expect(lines.contains { $0.amountCents == 120 && $0.title.contains("Apple") })
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

extension LififyRuleTests {
    /// Forecast interest on the depot's cash account compounds month by month.
    @Suite("Cash interest forecast")
    @MainActor
    struct CashInterestTests {
        @Test func interestIsPaidMonthlyAndCompounds() async throws {
            try await withTestStore { store in
                let now = date(2026, 3, 18, 12)
                FinanceClock.fix(now)
                defer { FinanceClock.fix(nil) }
                let trade = Account(name: "Trade Republic")
                store.context.insert(trade)
                store.context.insert(LedgerEntry(date: date(2026, 3, 1), title: "Startsaldo", amountCents: 1_000_000, kind: .adjustment, accountID: trade.id))
                try store.context.save()
                let entries: [LedgerEntry] = try store.all()
                let april = ForecastPeriod(start: date(2026, 4, 1), end: date(2026, 4, 30))
                let may = ForecastPeriod(start: date(2026, 5, 1), end: date(2026, 5, 31))
                @MainActor func income(_ period: ForecastPeriod) -> Int {
                    FinanceService.periodForecast(
                        period: period, periods: [april, may], accounts: [trade], entries: entries, holdings: [],
                        fixedCosts: [], variableBudgets: [], splits: [], forecasts: [], shopping: [], now: now
                    ).income
                }
                #expect(income(april) == 0)
                store.defaults.set(true, forKey: CashInterest.enabledKey)
                #expect(income(april) == 2_083)
                let aprilInterest = FinanceService.periodForecast(
                    period: april, periods: [april, may], accounts: [trade], entries: entries, holdings: [],
                    fixedCosts: [], variableBudgets: [], splits: [], forecasts: [], shopping: [], now: now
                ).interest
                #expect(aprilInterest.map(\.cents) == [2_083])
                #expect(income(may) == CashInterest.monthlyCents(on: 1_002_083, percent: 2.5))
                #expect(income(may) == 2_088)
                store.defaults.set(3.0, forKey: CashInterest.rateKey)
                #expect(income(april) == 2_500)
            }
        }

        @Test func monthEndsPayOnTheNextFirst() {
            let payouts = CashInterest.payouts(after: date(2026, 3, 18), through: date(2026, 5, 31))
            #expect(payouts.count == 2)
            #expect(Calendar.current.isDate(payouts[0].payout, inSameDayAs: date(2026, 4, 1)))
            #expect(Calendar.current.isDate(payouts[0].monthEnd, inSameDayAs: date(2026, 3, 31)))
            #expect(CashInterest.monthlyCents(on: -500, percent: 2.5) == 0)
        }
    }
}
