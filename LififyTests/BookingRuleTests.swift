import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing

extension LififyRuleTests {
    /// Variable costs take new bookings by IBAN or name, and imports and notices wait for a check.
    @Suite("Booking rules and assignment check")
    @MainActor
    struct BookingRuleTests {
        private let reweIBAN = "DE44 5001 0517 5407 3249 31"

        @Test func rulesMatchByIBANOrNameAndRespectTheAccounts() async throws {
            try await withTestStore { store in
                let giro = Account(name: "Giro", isMain: true)
                let other = Account(name: "Zweitkonto")
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                [giro, other].forEach(store.context.insert)
                store.context.insert(food)
                BudgetPayeeRules.set(["rewe", reweIBAN, " ", "REWE"], for: food.id)
                #expect(BudgetPayeeRules.rules(for: food.id) == ["rewe", reweIBAN])
                #expect(BudgetPayeeRules.isIBAN(reweIBAN))
                #expect(!BudgetPayeeRules.isIBAN("rewe"))

                let byName = LedgerEntry(title: "REWE Markt GmbH/Berlin", amountCents: -2_300, kind: .expense, accountID: giro.id)
                let byIBAN = LedgerEntry(title: "Kartenzahlung", notes: "Empfänger-IBAN: DE44500105175407324931", amountCents: -900, kind: .expense, accountID: giro.id)
                let none = LedgerEntry(title: "Aral", amountCents: -4_000, kind: .expense, accountID: giro.id)
                #expect(BudgetPayeeRules.budget(for: byName, in: [food])?.id == food.id)
                #expect(BudgetPayeeRules.budget(for: byIBAN, in: [food])?.id == food.id)
                #expect(BudgetPayeeRules.budget(for: none, in: [food]) == nil)

                VariableBudgetAccounts.set([other.id], for: food.id)
                #expect(BudgetPayeeRules.budget(for: byName, in: [food]) == nil)
                #expect(LinkKind.financeRecords.contains(.variableBudgetPayees))
                #expect(LinkKind.neverBackedUp.contains(.assignmentInbox))
            }
        }

        @Test func aPickedBookingBecomesARuleAndIsAssignedWhenFree() async throws {
            try await withTestStore { store in
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(food)
                let byIBAN = LedgerEntry(title: "Kartenzahlung", notes: "Empfänger-IBAN: DE44500105175407324931", amountCents: -900, kind: .expense)
                let byName = LedgerEntry(title: "REWE Markt/Berlin", amountCents: -2_300, kind: .expense)
                let short = LedgerEntry(title: "XY", amountCents: -100, kind: .expense)
                let taken = LedgerEntry(title: "REWE", amountCents: -500, kind: .expense, fixedCostID: UUID())
                #expect(BudgetPayeeRules.rule(from: byIBAN) == "DE44500105175407324931")
                #expect(BudgetPayeeRules.rule(from: byName) == "REWE Markt")
                #expect(BudgetPayeeRules.rule(from: short) == nil)
                #expect(BudgetPayeeRules.assign([byIBAN, byName, taken], to: food.id) == 2)
                #expect(byName.variableBudgetID == food.id)
                #expect(taken.variableBudgetID == nil)
            }
        }

        @Test func payeesAreGroupedAndARuleCoversThePast() async throws {
            try await withTestStore { store in
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(food)
                let march = LedgerEntry(date: date(2026, 3, 2), title: "REWE Markt/Berlin", amountCents: -2_300, kind: .expense)
                let april = LedgerEntry(date: date(2026, 4, 2), title: "REWE Markt/Hamburg", amountCents: -1_700, kind: .expense)
                let fuel = LedgerEntry(date: date(2026, 4, 3), title: "Aral", amountCents: -4_000, kind: .expense)
                let taken = LedgerEntry(date: date(2026, 4, 4), title: "REWE Markt", amountCents: -500, kind: .expense, fixedCostID: UUID())
                let all = [march, april, fuel, taken]
                let groups = BudgetPayeeRules.payeeGroups(in: all)
                let rewe = try #require(groups.first { $0.rule == "REWE Markt" })
                #expect(groups.count == 2)
                #expect(rewe.count == 3)
                #expect(rewe.totalCents == 4_500)
                #expect(Calendar.current.isDate(rewe.lastDate, inSameDayAs: date(2026, 4, 4)))
                BudgetPayeeRules.set([rewe.rule], for: food.id)
                #expect(BudgetPayeeRules.applyToExisting(food, entries: all) == 2)
                #expect(march.variableBudgetID == food.id && april.variableBudgetID == food.id)
                #expect(fuel.variableBudgetID == nil && taken.variableBudgetID == nil)
            }
        }

        @Test func poolsTakeNewAndEarlierBookingsByRule() async throws {
            try await withTestStore { store in
                let pool = BudgetPool(name: "Freizeit", amountCents: 20_000, accountID: nil, periodMode: .calendarYear, salaryStartDay: 1, isScalable: false)
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(pool)
                store.context.insert(food)
                let earlier = LedgerEntry(date: date(2026, 3, 2), title: "Kino Cinestar", amountCents: -1_500, kind: .expense)
                let other = LedgerEntry(date: date(2026, 3, 3), title: "Aral", amountCents: -4_000, kind: .expense)
                [earlier, other].forEach(store.context.insert)
                try store.context.save()
                BudgetPayeeRules.set(["kino"], for: pool.id, owner: .budgetPool)
                #expect(BudgetPayeeRules.rules(for: pool.id).isEmpty)
                #expect(PoolPayeeRules.applyToExisting(pool, entries: [earlier, other], context: store.context) == 1)
                #expect(PoolPayeeRules.applyToExisting(pool, entries: [earlier, other], context: store.context) == 0)
                #expect(PoolPayeeRules.poolID(of: earlier, context: store.context) == pool.id)

                BudgetPayeeRules.set(["kino"], for: food.id)
                let fresh = LedgerEntry(date: date(2026, 4, 2), title: "KINO Cinestar", amountCents: -1_200, kind: .expense)
                store.context.insert(fresh)
                let assigned = BookingAutoAssign.apply(to: [fresh], context: store.context)
                #expect(assigned.map(\.id) == [fresh.id])
                #expect(fresh.variableBudgetID == food.id)
                #expect(PoolPayeeRules.poolID(of: fresh, context: store.context) == pool.id)
                let split = try #require(try store.context.fetch(FetchDescriptor<TransactionSplit>()).first { $0.transactionID == fresh.id })
                #expect(split.amountCents == 1_200)
                #expect(LinkKind.financeRecords.contains(.budgetPoolPayees))
            }
        }

        @Test func autoAssignPrefersTheFixedCostAndNeverOverwritesAChoice() async throws {
            try await withTestStore { store in
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                let cost = FixedCost(name: "Rewe Lieferabo", amountCents: 999)
                store.context.insert(food)
                store.context.insert(cost)
                BudgetPayeeRules.set(["rewe"], for: food.id)
                let shop = LedgerEntry(title: "REWE", amountCents: -2_300, kind: .expense)
                let chosen = LedgerEntry(title: "REWE", amountCents: -500, kind: .expense, shoppingItemID: UUID())
                [shop, chosen].forEach(store.context.insert)
                let assigned = BookingAutoAssign.apply(to: [shop, chosen], context: store.context)
                #expect(assigned.map(\.id) == [shop.id])
                #expect(shop.variableBudgetID == food.id)
                #expect(chosen.variableBudgetID == nil)

                BookingTarget.fixedCost(cost.id).apply(to: shop)
                #expect(shop.fixedCostID == cost.id && shop.variableBudgetID == nil)
                #expect(BookingTarget(of: shop) == .fixedCost(cost.id))
                BookingTarget.none.apply(to: shop)
                #expect(BookingTarget(of: shop) == .none)
            }
        }

        @Test func aNoticeIsAssignedAndWaitsForTheCheck() async throws {
            try await withTestStore { store in
                store.context.insert(Account(name: "Sparkasse Giro", isMain: true))
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(food)
                try store.context.save()
                BudgetPayeeRules.set(["Bäckerei"], for: food.id)
                BankNoticeIntake.commit(text: "Du hast 12,50 € bei Bäckerei Müller ausgegeben", bank: .sparkasse, context: store.context)
                let entries = try store.context.fetch(FetchDescriptor<LedgerEntry>())
                let booked = try #require(entries.first { $0.amountCents == -1_250 })
                #expect(booked.variableBudgetID == food.id)
                #expect(AssignmentInbox.waitingSources(context: store.context) == [.notice])
                #expect(AssignmentInbox.pending(.notice, in: entries).map(\.id) == [booked.id])
                AssignmentInbox.clear([booked.id])
                #expect(AssignmentInbox.waitingSources(context: store.context).isEmpty)
            }
        }

        @Test func anImportReportsItsAutomaticAssignments() async throws {
            try await withTestStore { store in
                let giro = Account(name: "Giro", isMain: true)
                store.context.insert(giro)
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(food)
                try store.context.save()
                BudgetPayeeRules.set(["rewe"], for: food.id)
                let rows = [
                    BankImportService.imported(
                        date: date(2026, 3, 2), title: "REWE Markt", amount: -2_300, senderIBAN: "", recipientIBAN: "",
                        legacyIBAN: "", legacyTitle: "REWE Markt", details: "", trade: nil, distinct: "a"
                    ),
                    BankImportService.imported(
                        date: date(2026, 3, 3), title: "Aral", amount: -4_000, senderIBAN: "", recipientIBAN: "",
                        legacyIBAN: "", legacyTitle: "Aral", details: "", trade: nil, distinct: "b"
                    )
                ]
                let result = try BankImportApplier.apply(
                    document: BankImportDocument(rows: rows, tradeRepublic: nil),
                    to: .account(giro.id),
                    context: store.context
                )
                let entries = try store.context.fetch(FetchDescriptor<LedgerEntry>())
                let rewe = try #require(entries.first { $0.title == "REWE Markt" })
                #expect(result.autoAssignedIDs == [rewe.id])
                #expect(rewe.variableBudgetID == food.id)
                #expect(AssignmentInbox.waitingSources(context: store.context) == [.bankImport])
            }
        }
    }
}
