import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Warnings come once per threshold and period, for the running period only.
    @Suite("Budget alerts")
    @MainActor
    struct BudgetAlertTests {
        private let now = date(2026, 3, 18)

        /// Inserts a budget with the spending of one booking.
        private func budget(_ store: TestStore, limit: Int, spent: Int, on day: Date? = nil) -> VariableBudget {
            let budget = VariableBudget(name: "Essen", monthlyAmountCents: limit)
            store.context.insert(budget)
            store.context.insert(LedgerEntry(date: day ?? date(2026, 3, 5), title: "REWE", amountCents: spent, kind: .expense, variableBudgetID: budget.id))
            return budget
        }

        /// Runs a check over the stored budgets.
        private func evaluate(_ store: TestStore, settings: BudgetAlertSettings = .init(), sent: Set<String> = []) throws -> BudgetAlerts.Evaluation {
            try BudgetAlerts.evaluate(
                .init(budgets: store.all(), pools: store.all(), entries: store.all(), splits: store.all(), home: nil),
                settings: settings, sent: sent, now: now
            )
        }

        @Test func belowTheThresholdStaysSilent() async throws {
            try await withTestStore { store in
                _ = budget(store, limit: 10_000, spent: 7_999)
                try #expect(evaluate(store).alerts.isEmpty)
            }
        }

        @Test func eachThresholdWarnsOnce() async throws {
            try await withTestStore { store in
                let food = budget(store, limit: 10_000, spent: 8_000)
                let first = try evaluate(store)
                #expect(first.alerts.count == 1)
                try #expect(evaluate(store, sent: first.sent).alerts.isEmpty)
                store.context.insert(LedgerEntry(date: date(2026, 3, 6), title: "REWE", amountCents: 2_000, kind: .expense, variableBudgetID: food.id))
                let second = try evaluate(store, sent: first.sent)
                #expect(second.alerts.map(\.text) == [L("Essen: 100 % verbraucht", "Essen: 100 % used")])
                try #expect(evaluate(store, sent: second.sent).alerts.isEmpty)
            }
        }

        @Test func aJumpPastBothThresholdsWarnsOnce() async throws {
            try await withTestStore { store in
                _ = budget(store, limit: 10_000, spent: 12_000)
                let result = try evaluate(store)
                #expect(result.alerts.count == 1)
                #expect(result.sent.count == 2)
            }
        }

        @Test func oldBookingsDoNotWarn() async throws {
            try await withTestStore { store in
                _ = budget(store, limit: 10_000, spent: 50_000, on: date(2026, 1, 5))
                try #expect(evaluate(store).alerts.isEmpty)
            }
        }

        @Test func aNewMonthWarnsAgain() async throws {
            try await withTestStore { store in
                let food = budget(store, limit: 10_000, spent: 9_000)
                let march = try evaluate(store)
                store.context.insert(LedgerEntry(date: date(2026, 4, 2), title: "REWE", amountCents: 9_000, kind: .expense, variableBudgetID: food.id))
                let april = try BudgetAlerts.evaluate(
                    .init(budgets: store.all(), pools: [], entries: store.all(), splits: [], home: nil),
                    settings: .init(), sent: march.sent, now: date(2026, 4, 3)
                )
                #expect(april.alerts.count == 1)
            }
        }

        @Test func poolsWarnWithTheirCarry() async throws {
            try await withTestStore { store in
                let pool = BudgetPool(name: "Freizeit", amountCents: 10_000, periodMode: BudgetPeriodMode.allCases.first!)
                store.context.insert(pool)
                let entry = LedgerEntry(date: date(2026, 3, 5), title: "Kino", amountCents: 9_000, kind: .expense)
                store.context.insert(entry)
                store.context.insert(TransactionSplit(transactionID: entry.id, targetID: pool.id, kind: .budgetPool, periodKey: CalendarService.periodKey(for: now, pool: pool), amountCents: 9_000))
                try #expect(evaluate(store).alerts.count == 1)
            }
        }

        @Test func switchesTurnWarningsOff() async throws {
            try await withTestStore { store in
                _ = budget(store, limit: 10_000, spent: 9_000)
                var off = BudgetAlertSettings()
                off.enabled = false
                try #expect(evaluate(store, settings: off).alerts.isEmpty)
                var noBudgets = BudgetAlertSettings()
                noBudgets.budgets = false
                try #expect(evaluate(store, settings: noBudgets).alerts.isEmpty)
                var later = BudgetAlertSettings()
                later.firstPercent = 95
                try #expect(evaluate(store, settings: later).alerts.isEmpty)
            }
        }

        @Test func severalWarningsArriveAsOneMessage() {
            let single = BudgetAlerts.message(for: [BudgetAlert(key: "a", text: "A")])
            #expect(single?.body == "A")
            let bundled = BudgetAlerts.message(for: [BudgetAlert(key: "a", text: "A"), BudgetAlert(key: "b", text: "B")])
            #expect(bundled?.body == "A\nB")
            #expect(BudgetAlerts.message(for: []) == nil)
        }

        @Test func theDailyBudgetCountsTodaysSpending() async throws {
            try await withTestStore { store in
                let forecast = IncomeForecast(name: "Gehalt", amountCents: 100_000, firstPaymentDate: date(2026, 1, 28), dayOfMonth: 28)
                let giro = Account(name: "Giro", isMain: true)
                [giro].forEach(store.context.insert)
                store.context.insert(forecast)
                IncomeAssignmentStore.setPrimary(iban: "DE1", forecastID: forecast.id)
                store.context.insert(LedgerEntry(date: date(2026, 3, 1), title: "Gehalt", amountCents: 10_000, kind: .income, accountID: giro.id))
                store.context.insert(LedgerEntry(date: now, title: "Teuer", amountCents: 20_000, kind: .expense, accountID: giro.id))
                try store.context.save()
                let home = try HomeBudget.make(entries: store.all(), accounts: store.all(), forecasts: store.all(), variableBudgets: [], pools: [], splits: [], dashboardPeriod: DashboardPeriodMode.calendarMonth.rawValue, now: now)
                #expect(home.spentToday(now: now) == 20_000)
                let overrun = try #require(home.dailyOverrun(now: now))
                #expect(overrun == 9_000)
                let result = try BudgetAlerts.evaluate(.init(budgets: [], pools: [], entries: store.all(), splits: [], home: home), settings: .init(), sent: [], now: now)
                #expect(result.alerts.count == 1)
                let again = try BudgetAlerts.evaluate(.init(budgets: [], pools: [], entries: store.all(), splits: [], home: home), settings: .init(), sent: result.sent, now: now)
                #expect(again.alerts.isEmpty)
            }
        }
    }
}
