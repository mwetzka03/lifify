import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// Saveback is cashback paid by Trade Republic, not a purchase from the cash account.
    @Suite("Saveback repair")
    @MainActor
    struct SavebackRepairTests {
        @Test func aSavebackPurchaseBecomesCashbackOnTheDepot() async throws {
            try await withTestStore { store in
                let trade = Account(name: "Trade Republic")
                let depot = Account(name: "Depot", kind: .portfolio)
                [trade, depot].forEach(store.context.insert)
                let holding = PortfolioHolding(accountID: depot.id, name: "MSCI World USD (Acc)", symbol: "IE00BJ0KDQ92", quantity: 0.105152, purchasePriceCents: 14_265, currentPriceCents: 14_360)
                store.context.insert(holding)
                let day = date(2026, 11, 2, 15)
                let entry = LedgerEntry(
                    date: day, title: "Kauf: MSCI World USD (Acc)",
                    notes: "Typ: Handel\nISIN: IE00BJ0KDQ92\nStück: 0.105152\nEreignis: SAVEBACK_AGGREGATE",
                    amountCents: 1_500, kind: .transfer, fromAccountID: trade.id, toAccountID: depot.id
                )
                store.context.insert(entry)
                HoldingLotStore.replace([HoldingLot(date: day, quantity: 0.105152, unitPriceCents: 14_265, amountCents: 1_500, isSale: false, isSavingsPlan: false, ledgerEntryID: entry.id)], holdingID: holding.id)
                try store.context.save()
                #expect(SavebackRepair.run(context: store.context) == 1)
                #expect(entry.kind == .income)
                #expect(entry.accountID == depot.id)
                #expect(entry.fromAccountID == nil)
                #expect(entry.title == "Cashback: MSCI World USD (Acc)")
                #expect(BookingClassification.category(of: entry, accounts: [trade, depot], viewedAccountID: nil) == .cashback)
                #expect(HoldingLotStore.lots(for: holding.id).first?.source == "cashback")
                let entries: [LedgerEntry] = try store.all()
                #expect(FinanceService.currentBalance(for: trade, entries: entries) == 0)
                let performance = holdingPerformance(holding)
                #expect(performance.purchaseBase == 0)
                #expect(performance.purchaseCents == performance.value)
                #expect(SavebackRepair.run(context: store.context) == 0)
            }
        }

        @Test func anOrdinaryPurchaseStays() async throws {
            try await withTestStore { store in
                let entry = LedgerEntry(date: date(2026, 11, 2), title: "Kauf: Apple", notes: "Typ: Handel\nEreignis: TRADING_TRADE_EXECUTED", amountCents: 1_500, kind: .transfer)
                store.context.insert(entry)
                try store.context.save()
                #expect(SavebackRepair.run(context: store.context) == 0)
                #expect(entry.kind == .transfer)
            }
        }
    }
}
