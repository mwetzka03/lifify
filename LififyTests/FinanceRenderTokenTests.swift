import Foundation
import LififyCore
import LififyFinance
import Testing

extension LififyRuleTests {
    /// The finance summary recalculates when a planning value changes, not only when a row is added.
    @Suite("Finance render token")
    struct FinanceRenderTokenTests {
        /// The token of a list of rows.
        private func token<Item: FinanceTokenItem>(_ items: [Item]) -> Int {
            var hasher = Hasher()
            FinanceRenderToken.mix(items, into: &hasher)
            return hasher.finalize()
        }

        @Test func editingAFixedCostChangesTheToken() {
            let cost = FixedCost(name: "Miete", amountCents: 80_000, cadence: .monthly, firstChargeDate: date(2026, 3, 1))
            let before = token([cost])
            cost.amountCents = 85_000
            #expect(token([cost]) != before)
            let amount = token([cost])
            cost.isActive = false
            #expect(token([cost]) != amount)
        }

        @Test func editingABudgetOrForecastChangesTheToken() {
            let budget = VariableBudget(name: "Essen", monthlyAmountCents: 30_000)
            let budgetBefore = token([budget])
            budget.monthlyAmountCents = 35_000
            #expect(token([budget]) != budgetBefore)
            let income = IncomeForecast(name: "Lohn", amountCents: 300_000, cadence: .monthly, firstPaymentDate: date(2026, 3, 1))
            let incomeBefore = token([income])
            income.dayOfMonth = 15
            #expect(token([income]) != incomeBefore)
        }

        @Test func aRenameAloneKeepsTheToken() {
            let cost = FixedCost(name: "Miete", amountCents: 80_000, cadence: .monthly, firstChargeDate: date(2026, 3, 1))
            let before = token([cost])
            cost.name = "Wohnung"
            #expect(token([cost]) == before)
        }
    }
}
