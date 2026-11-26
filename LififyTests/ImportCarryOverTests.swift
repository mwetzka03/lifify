import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing

extension LififyRuleTests {
    /// Changes the person made to bookings survive a repeated import, and a fixed cost can start from a booking.
    @Suite("Import carry-over and fixed cost from booking")
    @MainActor
    struct ImportCarryOverTests {
        private let traderIBAN = "DE11100110012620000000"

        /// One card payment row of a Trade Republic statement.
        private func cardRow(_ day: Date, _ title: String, _ cents: Int, recipient: String = "") -> ImportedTransaction {
            BankImportService.imported(
                date: day, title: title, amount: cents, senderIBAN: "", recipientIBAN: recipient,
                legacyIBAN: recipient, legacyTitle: title, details: "Typ: Kartenzahlung",
                trade: nil, distinct: title
            )
        }

        /// Imports the statement and returns the checking account.
        @discardableResult
        private func importStatement(_ rows: [ImportedTransaction], into account: UUID?, context: ModelContext) throws -> UUID {
            let statement = TradeRepublicStatement(iban: traderIBAN, openingBalanceCents: 10_000, closingBalanceCents: 10_000 + rows.reduce(0) { $0 + $1.amountCents }, rows: rows)
            let result = try BankImportApplier.apply(
                document: BankImportDocument(rows: rows, tradeRepublic: statement),
                to: account.map { .account($0) } ?? .separateChecking,
                context: context
            )
            return result.checkingAccountID
        }

        @Test func aRepeatedStatementKeepsRefundLinksAssignmentsAndSplits() async throws {
            try await withTestStore { store in
                store.context.insert(Account(name: "Giro", isMain: true))
                try store.context.save()
                let rows = [cardRow(date(2026, 3, 2), "Shop", -5_000), cardRow(date(2026, 3, 5), "Shop Gutschrift", 2_000)]
                let account = try importStatement(rows, into: nil, context: store.context)
                let first = try store.context.fetch(FetchDescriptor<LedgerEntry>())
                let expense = try #require(first.first { $0.title == "Shop" })
                let refund = try #require(first.first { $0.title == "Shop Gutschrift" })
                let cost = FixedCost(name: "Shop", amountCents: 5_000)
                store.context.insert(cost)
                expense.fixedCostID = cost.id
                RefundLinkStore.link(refundID: refund.id, to: expense.id)
                IconPreferenceStore.set("bag", for: expense.id)
                store.context.insert(TransactionSplit(transactionID: expense.id, targetID: UUID(), kind: .budgetPool, periodKey: "2026-03", amountCents: 1_000))
                try store.context.save()

                try importStatement(rows, into: account, context: store.context)

                let second = try store.context.fetch(FetchDescriptor<LedgerEntry>())
                let newExpense = try #require(second.first { $0.title == "Shop" })
                let newRefund = try #require(second.first { $0.title == "Shop Gutschrift" })
                #expect(second.filter { $0.title == "Shop" }.count == 1)
                #expect(newExpense.fixedCostID == cost.id)
                #expect(RefundLinkStore.originalID(for: newRefund.id) == newExpense.id)
                #expect(IconPreferenceStore.storedIcon(for: newExpense.id) == "bag")
                let splits = try store.context.fetch(FetchDescriptor<TransactionSplit>())
                #expect(splits.map(\.transactionID) == [newExpense.id])
            }
        }

        @Test func aFixedCostFromABookingTakesTheSamePayeeAndAssignsNewImports() async throws {
            try await withTestStore { store in
                let account = Account(name: "Giro", isMain: true)
                store.context.insert(account)
                let iban = "DE89370400440532013000"
                let gym = [
                    LedgerEntry(date: date(2026, 1, 3), title: "FitX GmbH", notes: "Empfänger-IBAN: \(iban)", amountCents: -2_999, kind: .expense, accountID: account.id),
                    LedgerEntry(date: date(2026, 2, 3), title: "FitX GmbH Beitrag", notes: "Empfänger-IBAN: \(iban)", amountCents: -3_499, kind: .expense, accountID: account.id),
                    LedgerEntry(date: date(2026, 3, 3), title: "FITX", notes: "Empfänger-IBAN: \(iban)", amountCents: -3_499, kind: .expense, accountID: account.id)
                ]
                let other = LedgerEntry(date: date(2026, 3, 4), title: "Bäcker", amountCents: -350, kind: .expense, accountID: account.id)
                (gym + [other]).forEach(store.context.insert)
                try store.context.save()

                let related = FixedCostFromBooking.related(to: gym[2], in: gym + [other])
                #expect(related.map(\.id) == gym.reversed().map(\.id))
                let cost = FixedCostFromBooking.create(name: "Fitnessstudio", source: gym[2], chosen: related, icon: "dumbbell", context: store.context)
                #expect(cost.amountCents == 3_499)
                #expect(cost.cadence == .monthly)
                #expect(gym.allSatisfy { $0.fixedCostID == cost.id })
                #expect(IconPreferenceStore.storedIcon(for: cost.id) == "dumbbell")

                let april = LedgerEntry(date: date(2026, 4, 3), title: "FitX", notes: "Empfänger-IBAN: \(iban)", amountCents: -3_999, kind: .expense, accountID: account.id)
                let bakery = LedgerEntry(date: date(2026, 4, 4), title: "Bäcker", amountCents: -400, kind: .expense, accountID: account.id)
                let assigned = FixedCostFromBooking.assign(newEntries: [april, bakery], costs: [cost])
                #expect(assigned == 1)
                #expect(april.fixedCostID == cost.id)
                #expect(bakery.fixedCostID == nil)
                #expect(LinkKind.financeRecords.contains(.fixedCostPayee))
            }
        }

        @Test func anIncomeLinksToAnExpenseAndBookingsShowTheFixedCostIcon() async throws {
            try await withTestStore { store in
                let shoes = LedgerEntry(date: date(2026, 3, 1), title: "Zalando", amountCents: -8_000, kind: .expense)
                let food = LedgerEntry(date: date(2026, 3, 9), title: "Rewe", amountCents: -2_000, kind: .expense)
                let later = LedgerEntry(date: date(2026, 3, 20), title: "Zalando", amountCents: -1_000, kind: .expense)
                let back = LedgerEntry(date: date(2026, 3, 12), title: "Zalando Erstattung", amountCents: 8_000, kind: .income)
                [shoes, food, later, back].forEach(store.context.insert)
                let offered = RefundCandidates.expenses(for: back, in: [shoes, food, later, back])
                #expect(offered.map(\.id) == [shoes.id, food.id])
                RefundLinkStore.link(refundID: back.id, to: shoes.id)
                #expect(BookingClassification.category(of: back, accounts: [], viewedAccountID: nil) == .refund)
                #expect(RefundCandidates.expenses(for: back, in: [shoes, back]).map(\.id) == [shoes.id])

                let cost = FixedCost(name: "Netflix", amountCents: 1_299)
                IconPreferenceStore.set("tv", for: cost.id)
                food.fixedCostID = cost.id
                #expect(BookingSymbol.name(for: food, category: .expense) == "tv")
                #expect(BookingSymbol.name(for: later, category: .expense) == BookingCategory.expense.systemImage)
            }
        }
    }
}
