import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// The review compares a finished period with earlier ones, by category.
    @Suite("Period review")
    @MainActor
    struct PeriodReviewTests {
        private let now = date(2026, 5, 10)

        /// Calendar months from January through May.
        private var periods: [ForecastPeriod] {
            FinanceService.forecastPeriods(primary: nil, earliest: date(2026, 1, 1), latest: now)
        }

        /// Builds the review from the store.
        private func review(_ store: TestStore, from start: Date = date(2026, 1, 1, 0)) throws -> PeriodReview? {
            try PeriodReviewBuilder.make(
                .init(entries: store.all(), splits: store.all(), costs: store.all(), budgets: store.all(), pools: store.all()),
                periods: periods.filter { $0.start >= start },
                now: now
            )
        }

        /// Inserts an expense.
        private func expense(_ store: TestStore, _ month: Int, _ cents: Int, budget: UUID? = nil, cost: UUID? = nil) -> LedgerEntry {
            let entry = LedgerEntry(date: date(2026, month, 10), title: "Zahlung", amountCents: cents, kind: .expense, fixedCostID: cost, variableBudgetID: budget)
            store.context.insert(entry)
            return entry
        }

        @Test func comparesTheLastFinishedPeriodWithTheAverage() async throws {
            try await withTestStore { store in
                let food = VariableBudget(name: "Essen", monthlyAmountCents: 40_000)
                store.context.insert(food)
                _ = expense(store, 2, 10_000, budget: food.id)
                _ = expense(store, 3, 20_000, budget: food.id)
                _ = expense(store, 4, 45_000, budget: food.id)
                _ = expense(store, 5, 99_000, budget: food.id)
                try store.context.save()
                let result = try #require(try review(store))
                #expect(result.period.contains(date(2026, 4, 15)))
                #expect(result.totalCents == 45_000)
                #expect(result.comparedPeriods == 3)
                #expect(result.averageTotalCents == 10_000)
                #expect(result.lines.first?.title == "Essen")
                #expect(result.lines.first?.differenceCents == 35_000)
            }
        }

        @Test func theLargestDeviationComesFirstInEitherDirection() async throws {
            try await withTestStore { store in
                let rent = FixedCost(name: "Miete", amountCents: 80_000)
                let food = VariableBudget(name: "Essen", monthlyAmountCents: 40_000)
                store.context.insert(rent)
                store.context.insert(food)
                _ = expense(store, 3, 80_000, cost: rent.id)
                _ = expense(store, 3, 30_000, budget: food.id)
                _ = expense(store, 4, 80_000, cost: rent.id)
                _ = expense(store, 4, 5_000, budget: food.id)
                _ = expense(store, 4, 1_000)
                try store.context.save()
                let result = try #require(try review(store, from: date(2026, 3, 1, 0)))
                #expect(result.lines.map(\.title) == ["Essen", L("Sonstiges", "Other"), "Miete"])
                #expect(result.lines[0].differenceCents < 0)
            }
        }

        @Test func refundsAndSplitsLandInTheRightCategory() async throws {
            try await withTestStore { store in
                let pool = BudgetPool(name: "Freizeit", amountCents: 15_000)
                store.context.insert(pool)
                let entry = expense(store, 4, 10_000)
                store.context.insert(TransactionSplit(transactionID: entry.id, targetID: pool.id, kind: .budgetPool, periodKey: "x", amountCents: 3_000))
                let refund = LedgerEntry(date: date(2026, 4, 12), title: "Erstattung", amountCents: 2_000, kind: .income)
                store.context.insert(refund)
                RefundLinkStore.link(refundID: refund.id, to: entry.id)
                try store.context.save()
                let lines = try #require(try review(store)).lines
                #expect(lines.first { $0.title == "Freizeit" }?.spentCents == 3_000)
                #expect(lines.first { $0.title == L("Sonstiges", "Other") }?.spentCents == 5_000)
            }
        }

        @Test func noFinishedPeriodMeansNoReview() async throws {
            try await withTestStore { store in
                let single = [ForecastPeriod(start: date(2026, 5, 1), end: date(2026, 5, 31))]
                #expect(PeriodReviewBuilder.make(
                    .init(entries: [], splits: [], costs: [], budgets: [], pools: []), periods: single, now: now
                ) == nil)
                try #expect(store.all(LedgerEntry.self).isEmpty)
            }
        }

        @Test func aPeriodIsAnnouncedOnceAndNotOnTheFirstCheck() async throws {
            try await withTestStore { store in
                let april = ForecastPeriod(start: date(2026, 4, 1), end: date(2026, 4, 30))
                let may = ForecastPeriod(start: date(2026, 5, 1), end: date(2026, 5, 31))
                #expect(PeriodReviewNotifier.periodToAnnounce(april) == nil)
                store.defaults.set(true, forKey: PeriodReviewNotifier.enabledKey)
                #expect(PeriodReviewNotifier.periodToAnnounce(april) == nil)
                #expect(PeriodReviewNotifier.periodToAnnounce(april) == nil)
                #expect(PeriodReviewNotifier.periodToAnnounce(may) == may)
                #expect(PeriodReviewNotifier.periodToAnnounce(may) == nil)
            }
        }
    }

    /// Repeated payments become suggestions until they are adopted or rejected.
    @Suite("Subscription detection")
    @MainActor
    struct SubscriptionDetectorTests {
        private let now = date(2026, 5, 20)

        /// Inserts one payment per given month.
        private func monthly(_ store: TestStore, _ title: String, _ cents: Int, months: [Int] = [2, 3, 4, 5], day: Int = 5) {
            for month in months {
                store.context.insert(LedgerEntry(date: date(2026, month, day), title: title, amountCents: cents, kind: .expense))
            }
        }

        /// Lists the current suggestions.
        private func found(_ store: TestStore) throws -> [SubscriptionSuggestion] {
            try SubscriptionDetector.suggestions(entries: store.all(), costs: store.all(), now: now)
        }

        @Test func findsAMonthlyPaymentWithASmallPriceChange() async throws {
            try await withTestStore { store in
                monthly(store, "Netflix / Amsterdam", -1_299, months: [2, 3])
                monthly(store, "NETFLIX", -1_399, months: [4, 5])
                let suggestion = try #require(try found(store).first)
                #expect(suggestion.cadence == .monthly)
                #expect(suggestion.occurrences == 4)
                #expect(suggestion.amountCents == 1_399)
            }
        }

        @Test func needsThreePaymentsAStableAmountAndARhythm() async throws {
            try await withTestStore { store in
                monthly(store, "Zweimal", -500, months: [4, 5])
                monthly(store, "Schwankt", -500, months: [2])
                monthly(store, "Schwankt", -900, months: [3])
                monthly(store, "Schwankt", -1_500, months: [4])
                for day in [1, 3, 20] {
                    store.context.insert(LedgerEntry(date: date(2026, 5, day), title: "Bäcker", amountCents: -300, kind: .expense))
                }
                try #expect(found(store).isEmpty)
            }
        }

        @Test func recognizesWeeklyAndYearlyPayments() async throws {
            try await withTestStore { store in
                for day in [1, 8, 15] {
                    store.context.insert(LedgerEntry(date: date(2026, 5, day), title: "Kurs", amountCents: -2_000, kind: .expense))
                }
                for year in [2024, 2025, 2026] {
                    store.context.insert(LedgerEntry(date: date(year, 3, 1), title: "Versicherung", amountCents: -12_000, kind: .expense))
                }
                let cadences = Dictionary(uniqueKeysWithValues: try found(store).map { ($0.title, $0.cadence) })
                #expect(cadences["Kurs"] == .weekly)
                #expect(cadences["Versicherung"] == .yearly)
            }
        }

        @Test func anEndedSubscriptionIsNotSuggested() async throws {
            try await withTestStore { store in
                monthly(store, "Altes Abo", -999, months: [1, 2, 3], day: 1)
                let old = try SubscriptionDetector.suggestions(entries: store.all(), costs: [], now: date(2026, 9, 1))
                #expect(old.isEmpty)
            }
        }

        @Test func anExistingFixedCostIsNotSuggested() async throws {
            try await withTestStore { store in
                monthly(store, "Spotify", -999)
                store.context.insert(FixedCost(name: "spotify", amountCents: 999))
                try #expect(found(store).isEmpty)
            }
        }

        @Test func aRejectionStaysAndIsPartOfTheBackup() async throws {
            try await withTestStore { store in
                monthly(store, "Spotify", -999)
                SubscriptionDetector.reject(try #require(try found(store).first))
                try #expect(found(store).isEmpty)
                #expect(LinkKind.financeRecords.contains(.subscriptionRejection))
            }
        }

        @Test func adoptingCreatesTheCostAndLinksThePayments() async throws {
            try await withTestStore { store in
                monthly(store, "Spotify", -999)
                let suggestion = try #require(try found(store).first)
                let cost = SubscriptionDetector.adopt(suggestion, entries: try store.all(), context: store.context)
                #expect(cost.amountCents == 999)
                #expect(cost.cadence == .monthly)
                #expect(cost.dayOfMonth == 5)
                #expect(cost.firstChargeDate == date(2026, 2, 5))
                try #expect(store.all(LedgerEntry.self).allSatisfy { $0.fixedCostID == cost.id })
                try #expect(found(store).isEmpty)
            }
        }
    }
}
