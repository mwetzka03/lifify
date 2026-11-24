import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing
@testable import Lifify

/// Finds the test bundle that carries the stored reference.
private final class ReferenceBundleMarker {}

/// Writes stored finance data as sorted text without random identifiers.
@MainActor
private struct MoneyDump {
    let store: TestStore
    private(set) var lines: [String] = []

    /// Adds a titled block of lines.
    mutating func section(_ title: String, _ rows: [String]) {
        lines.append("=== \(title)")
        lines += rows
    }

    /// Adds every stored finance row.
    mutating func ledger(_ title: String) throws {
        let accounts = try store.all(Account.self)
        let names = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let name = { (id: UUID?) in id.map { names[$0] ?? "?" } ?? "-" }
        section("\(title): accounts", accounts.map { "\($0.name)|\($0.kindRaw)|\($0.isLiquid)|\($0.isMain)|\($0.iban)|\(name($0.parentAccountID))" }.sorted())
        section("\(title): entries", try store.all(LedgerEntry.self).map {
            [Self.stamp($0.date), $0.title, $0.notes, String($0.amountCents), $0.kindRaw, name($0.accountID),
             name($0.fromAccountID), name($0.toAccountID), $0.importFingerprint ?? "-"]
                .joined(separator: "|").replacingOccurrences(of: "\n", with: "⏎")
        }.sorted())
        try depot(title, name: name)
        section("\(title): links", accounts.compactMap { account in
            PortfolioLinkStore.portfolioID(for: account.id).map { "\(account.name)->\(name($0))" }
        }.sorted())
    }

    /// Adds holdings, lots, plans, and closed positions.
    private mutating func depot(_ title: String, name: (UUID?) -> String) throws {
        var rows: [String] = []
        for holding in try store.all(PortfolioHolding.self) {
            let head = "\(holding.name)|\(holding.symbol)|\(name(holding.accountID))"
            rows.append("\(head)|\(Self.number(holding.quantity))|\(holding.purchasePriceCents)|\(holding.currentPriceCents)")
            rows += HoldingLotStore.lots(for: holding.id).map { "\(head)|lot|\(Self.lot($0))" }
        }
        section("\(title): holdings", rows.sorted())
        section("\(title): plans", SavingsPlanStore.all().map {
            "\($0.isin)|\($0.name)|\($0.amountCents)|\($0.cadenceRaw)|\(name($0.checkingAccountID))|\(name($0.portfolioAccountID))|\(Self.stamp($0.lastExecution))|\($0.active)"
        }.sorted())
        section("\(title): closed", ClosedPositionStore.all().flatMap { record in
            record.lots.map { "\(record.isin)|\(record.name)|\(Self.lot($0))" }
        }.sorted())
    }

    /// Formats one lot.
    private static func lot(_ lot: HoldingLot) -> String {
        "\(stamp(lot.date))|\(number(lot.quantity))|\(lot.unitPriceCents)|\(lot.amountCents)|\(lot.isSale)|\(lot.isSavingsPlan)|\(lot.source)|\(lot.ledgerEntryID != nil)"
    }

    /// Formats a date to the minute.
    static func stamp(_ date: Date?) -> String {
        guard let date else { return "-" }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return "\(date.dayKey) \(parts.hour ?? 0):\(parts.minute ?? 0)"
    }

    /// Formats a quantity with fixed precision.
    static func number(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

extension LififyRuleTests {
    /// Compares the money paths with a stored reference of their output.
    ///
    /// The reference was written by the code before its long methods were split. To write it
    /// again on purpose, run with `TEST_RUNNER_LIFIFY_REFERENCE_PATH` set to a file path.
    @Suite("Money reference")
    @MainActor
    struct MoneyReferenceTests {
        private let now = date(2026, 3, 18)
        private let giroIBAN = "DE89370400440532013000"
        private let savingsIBAN = "DE12500105170648489890"
        private let outsideIBAN = "DE75512108001245126199"

        /// Builds one imported row with a stable fingerprint.
        private func row(
            _ day: Date, _ title: String, _ cents: Int, sender: String = "", recipient: String = "",
            trade: ImportedSecurityTrade? = nil, purpose: String = ""
        ) -> ImportedTransaction {
            BankImportService.imported(
                date: day, title: title, amount: cents, senderIBAN: sender, recipientIBAN: recipient,
                legacyIBAN: sender.isEmpty ? recipient : sender, legacyTitle: title, details: purpose,
                trade: trade, distinct: purpose
            )
        }

        /// Runs a scenario at the fixed time.
        private func scenario(_ body: (TestStore, inout MoneyDump) async throws -> Void) async throws -> [String] {
            FinanceClock.fix(now)
            defer { FinanceClock.fix(nil) }
            return try await withTestStore { store in
                var dump = MoneyDump(store: store)
                try await body(store, &dump)
                return dump.lines
            }
        }

        /// Imports a statement, repeats it, answers the questions, and imports the other side.
        private func bankImport() async throws -> [String] {
            try await scenario { store, dump in
                let giro = Account(name: "Giro", isMain: true, iban: giroIBAN)
                let savings = Account(name: "Spar", kind: .savings, iban: savingsIBAN)
                store.context.insert(giro)
                store.context.insert(savings)
                try store.context.save()
                let first = BankImportDocument(rows: [
                    row(date(2026, 2, 27), "Gehalt", 250_000, sender: outsideIBAN, recipient: giroIBAN),
                    row(date(2026, 3, 1), "Miete", -80_000, sender: giroIBAN, recipient: outsideIBAN),
                    row(date(2026, 3, 3), "REWE", -4_599, sender: giroIBAN, recipient: outsideIBAN, purpose: "Karte 1"),
                    row(date(2026, 3, 4), "Sparen", -10_000, sender: giroIBAN, recipient: savingsIBAN),
                    row(date(2026, 3, 5), "Kauf ETF", -5_000, trade: ImportedSecurityTrade(isin: "IE00B4L5Y983", name: "World ETF", quantity: 2, isSale: false)),
                    row(date(2026, 3, 6), "Sparplan ETF", -2_500, trade: ImportedSecurityTrade(isin: "IE00B4L5Y983", name: "World ETF", quantity: 1, isSale: false, isSavingsPlan: true)),
                    row(date(2026, 3, 9), "Verkauf ETF", 3_000, trade: ImportedSecurityTrade(isin: "IE00B4L5Y983", name: "World ETF", quantity: 1, isSale: true)),
                    row(date(2026, 3, 10), "Dividende", 120, purpose: "Ertrag")
                ])
                let result = try BankImportApplier.apply(document: first, to: .account(giro.id), currentBalanceCents: 123_456, context: store.context)
                dump.section("first import", ["\(result.importedCount)|\(result.holdingCount)|\(result.accountName)|\(result.review.similar.count)"])
                try dump.ledger("first")

                let again = try BankImportApplier.apply(document: first, to: .account(giro.id), currentBalanceCents: 123_456, context: store.context)
                dump.section("repeat import", ["\(again.importedCount)|\(again.review.similar.count)"])
                try dump.ledger("repeat")

                let similar = BankImportDocument(rows: [
                    row(date(2026, 3, 2), "Nachzügler", -100, sender: giroIBAN, recipient: outsideIBAN),
                    row(date(2026, 3, 3), "REWE", -4_599, sender: giroIBAN, recipient: savingsIBAN + "0"),
                    row(date(2026, 3, 10), "Dividende", 120, sender: outsideIBAN),
                    row(date(2026, 3, 10), "Zusatz", -700, sender: giroIBAN, recipient: outsideIBAN),
                    row(date(2026, 3, 12), "Tanken", -6_000, sender: giroIBAN, recipient: outsideIBAN)
                ])
                var asked = try BankImportApplier.apply(document: similar, to: .account(giro.id), currentBalanceCents: 117_456, context: store.context).review
                dump.section("similar questions", asked.similar.map { "\($0.title)|\($0.signedAmountCents)|\($0.existingTitle)|\($0.isExtra)" }.sorted())
                for index in asked.similar.indices { asked.similar[index].include = true }
                try BankImportApplier.commitReview(asked, context: store.context)
                try dump.ledger("similar accepted")

                var known = Set(try store.all(LedgerEntry.self).compactMap(\.importFingerprint))
                var ledger = try store.all(LedgerEntry.self)
                var direct = ImportReview()
                let booked = BankImportApplier.ingestCashRow(
                    row(date(2026, 3, 12), "Tanken", -6_000, sender: giroIBAN, recipient: savingsIBAN + "1"),
                    checking: giro, accounts: try store.all(), entries: &ledger, known: &known, review: &direct, context: store.context
                )
                dump.section("direct row", ["\(booked != nil)|\(direct.similar.map(\.existingTitle))"])
                let other = BankImportDocument(rows: [row(date(2026, 3, 4), "Sparen", 10_000, sender: giroIBAN, recipient: savingsIBAN)])
                let transfer = try BankImportApplier.apply(document: other, to: .account(savings.id), currentBalanceCents: 10_000, context: store.context).review
                try BankImportApplier.commitReview(transfer, context: store.context)
                try dump.ledger("transfer accepted")
            }
        }

        /// Imports a Trade Republic PDF statement into a new account.
        private func statementImport() async throws -> [String] {
            try await scenario { store, dump in
                store.context.insert(Account(name: "Giro", isMain: true, iban: giroIBAN))
                try store.context.save()
                let rows = [
                    row(date(2026, 1, 5), "Einzahlung", 100_000, sender: giroIBAN),
                    row(date(2026, 1, 6), "Kauf Aktie", -30_000, trade: ImportedSecurityTrade(isin: "US0378331005", name: "Apple", quantity: 2, isSale: false)),
                    row(date(2026, 2, 2), "Sparplan", -5_000, trade: ImportedSecurityTrade(isin: "IE00B4L5Y983", name: "World ETF", quantity: 0.5, isSale: false, isSavingsPlan: true)),
                    row(date(2026, 3, 2), "Sparplan", -5_000, trade: ImportedSecurityTrade(isin: "IE00B4L5Y983", name: "World ETF", quantity: 0.5, isSale: false, isSavingsPlan: true)),
                    row(date(2026, 3, 9), "Verkauf Aktie", 16_000, trade: ImportedSecurityTrade(isin: "US0378331005", name: "Apple", quantity: 1, isSale: true)),
                    row(date(2026, 3, 10), "Zinsen", 250, purpose: "Zinsen")
                ]
                let statement = TradeRepublicStatement(iban: "DE11100110012620000000", openingBalanceCents: 0, closingBalanceCents: 76_250, rows: rows)
                let result = try BankImportApplier.apply(
                    document: BankImportDocument(rows: rows, tradeRepublic: statement),
                    to: .separateChecking, currentBalanceCents: 76_250, context: store.context
                )
                dump.section("statement", ["\(result.importedCount)|\(result.holdingCount)|\(result.accountName)|\(result.createdSeparateChecking)"])
                try dump.ledger("statement")
                let repeated = try BankImportApplier.apply(
                    document: BankImportDocument(rows: rows, tradeRepublic: statement),
                    to: .account(result.checkingAccountID), currentBalanceCents: 76_250, context: store.context
                )
                dump.section("statement repeat", ["\(repeated.importedCount)|\(repeated.holdingCount)"])
                try dump.ledger("statement repeat")
            }
        }

        /// Applies a live Trade Republic session twice.
        private func liveSession() async throws -> [String] {
            try await scenario { store, dump in
                store.context.insert(Account(name: "Giro", isMain: true, iban: giroIBAN))
                try store.context.save()
                let snapshot = TradeRepublicSnapshot(positions: [
                    TradeRepublicPosition(isin: "IE00B4L5Y983", name: "World ETF", quantity: 3.5, averageBuyInCents: 10_000),
                    TradeRepublicPosition(isin: "US0378331005", name: "Apple", quantity: 2, averageBuyInCents: 15_000),
                    TradeRepublicPosition(isin: "DE0007164600", name: "SAP", quantity: 1, averageBuyInCents: 0)
                ], activities: [
                    TradeRepublicActivity(id: "a1", date: date(2026, 1, 2), title: "Einzahlung", eventType: "PAYMENT_INBOUND", amountCents: 100_000, isin: "", trade: false, status: "EXECUTED", statementType: "Überweisung"),
                    TradeRepublicActivity(id: "a2", date: date(2026, 1, 5), title: "Apple", eventType: "ORDER_EXECUTED", amountCents: -45_000, isin: "US0378331005", trade: true, status: "EXECUTED", quantity: 3),
                    TradeRepublicActivity(id: "a3", date: date(2026, 2, 2), title: "World ETF", eventType: "SAVINGS_PLAN_EXECUTED", amountCents: -20_000, isin: "IE00B4L5Y983", trade: true, status: "EXECUTED", quantity: 2, savingsPlan: true),
                    TradeRepublicActivity(id: "a4", date: date(2026, 3, 2), title: "World ETF", eventType: "SAVINGS_PLAN_EXECUTED", amountCents: -15_000, isin: "IE00B4L5Y983", trade: true, status: "EXECUTED", quantity: 1.5, savingsPlan: true),
                    TradeRepublicActivity(id: "a5", date: date(2026, 3, 4), title: "Apple", eventType: "ORDER_EXECUTED", amountCents: 16_000, isin: "US0378331005", trade: true, status: "EXECUTED", quantity: 1),
                    TradeRepublicActivity(id: "a6", date: date(2026, 3, 5), title: "Tesla", eventType: "ORDER_EXECUTED", amountCents: -9_000, isin: "US88160R1014", trade: true, status: "EXECUTED", quantity: 1),
                    TradeRepublicActivity(id: "a7", date: date(2026, 3, 6), title: "Tesla", eventType: "ORDER_EXECUTED", amountCents: 9_500, isin: "US88160R1014", trade: true, status: "EXECUTED", quantity: 1),
                    TradeRepublicActivity(id: "a8", date: date(2026, 3, 7), title: "SAP", eventType: "GIFTING_RECIPIENT_ACTIVITY", amountCents: 0, isin: "DE0007164600", trade: false, status: "EXECUTED", statementType: "Depotgeschenk", quantity: 1),
                    TradeRepublicActivity(id: "a9", date: date(2026, 3, 9), title: "Apple", eventType: "SSP_CORPORATE_ACTION_CASH", amountCents: 320, isin: "US0378331005", trade: false, status: "EXECUTED", statementType: "Ertrag"),
                    TradeRepublicActivity(id: "a10", date: date(2026, 3, 10), title: "Zinsen", eventType: "INTEREST_PAYOUT", amountCents: 410, isin: "", trade: false, status: "EXECUTED", statementType: "Zinsen"),
                    TradeRepublicActivity(id: "a11", date: date(2026, 3, 11), title: "Bäcker", eventType: "CARD_TRANSACTION", amountCents: -350, isin: "", trade: false, status: "EXECUTED", statementType: "Kartentransaktion"),
                    TradeRepublicActivity(id: "a12", date: date(2026, 3, 12), title: "Offen", eventType: "ORDER_EXECUTED", amountCents: -999, isin: "US0378331005", trade: true, status: "PENDING", quantity: 1)
                ], plans: [
                    TradeRepublicPlan(isin: "IE00B4L5Y983", name: "World ETF", amountCents: 15_000, interval: "monthly", active: true),
                    TradeRepublicPlan(isin: "US0378331005", name: "Apple", amountCents: 2_500, interval: "weekly", active: false)
                ], cashCents: 41_230)
                dump.section("first session", [String(try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: store.context))])
                try dump.ledger("first session")
                dump.section("second session", [String(try await TradeRepublicDepotApplier.apply(snapshot: snapshot, context: store.context))])
                try dump.ledger("second session")
            }
        }

        /// Books bank notices, including a repeat, a transfer, and an unreadable text.
        private func notices() async throws -> [String] {
            try await scenario { store, dump in
                let giro = Account(name: "Sparkasse Giro", isMain: true)
                let depot = Account(name: "Trade Republic", iban: "DE11100110012620000000")
                store.context.insert(giro)
                store.context.insert(depot)
                try store.context.save()
                let calls: [(String, BankNoticeBank)] = [
                    ("Du hast 12,50 € bei Bäckerei Müller ausgegeben", .sparkasse),
                    ("Du hast 12,50 € bei Bäckerei Müller ausgegeben", .sparkasse),
                    ("Gutschrift +1.250,00 EUR Gehalt", .sparkasse),
                    ("Du hast 40,00 € bei Aral ausgegeben", .tradeRepublic),
                    ("Überweisung erhalten 100,00 €", .tradeRepublic),
                    ("Keine Zahl in diesem Text", .sparkasse)
                ]
                let answers = calls.map { BankNoticeIntake.commit(text: $0.0, bank: $0.1, context: store.context, now: now) }
                dump.section("notice answers", answers)
                try dump.ledger("notices")
            }
        }

        /// Links own-account bookings, and does so only once.
        private func bankLinks() async throws -> [String] {
            try await scenario { store, dump in
                let giro = Account(name: "Giro", isMain: true, iban: giroIBAN)
                let savings = Account(name: "Spar", kind: .savings, iban: savingsIBAN)
                let broker = Account(name: "Trade Republic", iban: "DE11100110012620000000")
                [giro, savings, broker].forEach(store.context.insert)
                seedOwnAccountBookings(store, giro: giro, savings: savings, broker: broker)
                try store.context.save()
                BankImportApplier.relinkOwnAccounts(context: store.context)
                try dump.ledger("linked")
                BankImportApplier.relinkOwnAccounts(context: store.context)
                try dump.ledger("linked again")
            }
        }

        /// Adds payments between own accounts, by IBAN and by naming Trade Republic.
        private func seedOwnAccountBookings(_ store: TestStore, giro: Account, savings: Account, broker: Account) {
            let rows = [
                LedgerEntry(date: date(2026, 3, 7), title: "An Spar", notes: "Empfänger-IBAN: \(savingsIBAN)", amountCents: -4_000, kind: .expense, accountID: giro.id),
                LedgerEntry(date: date(2026, 3, 8), title: "Von Giro", notes: "Sender-IBAN: \(giroIBAN)", amountCents: 4_000, kind: .income, accountID: savings.id),
                LedgerEntry(date: date(2026, 3, 9), title: "Schon da", notes: "Sender-IBAN: \(giroIBAN)", amountCents: 5_000, kind: .income, accountID: savings.id),
                LedgerEntry(date: date(2026, 3, 9), title: "Umbuchung", amountCents: 5_000, kind: .transfer, fromAccountID: giro.id, toAccountID: savings.id),
                LedgerEntry(date: date(2026, 3, 10), title: "Trade Republic Einzahlung", amountCents: -6_000, kind: .expense, accountID: giro.id),
                LedgerEntry(date: date(2026, 3, 11), title: "Einzahlung", amountCents: 6_000, kind: .income, accountID: broker.id),
                LedgerEntry(date: date(2026, 3, 12), title: "Trade Republic", amountCents: -7_000, kind: .expense, accountID: giro.id),
                LedgerEntry(date: date(2026, 3, 12), title: "Umbuchung TR", amountCents: 7_000, kind: .transfer, fromAccountID: giro.id, toAccountID: broker.id),
                LedgerEntry(date: date(2026, 3, 13), title: "Einzahlung", amountCents: 7_000, kind: .income, accountID: broker.id)
            ]
            // Saved one by one: when two rows mirror each other, the stored order decides which stays.
            for row in rows {
                store.context.insert(row)
                try? store.context.save()
            }
        }

        /// Seeds a household for the budget and forecast calculations.
        private func seedPlan(_ store: TestStore) throws -> (giro: Account, salary: IncomeForecast) {
            let giro = Account(name: "Giro", isMain: true, iban: giroIBAN)
            let savings = Account(name: "Spar", kind: .savings, iban: savingsIBAN)
            let depot = Account(name: "Depot", kind: .portfolio, isLiquid: false)
            let salary = IncomeForecast(name: "Gehalt", amountCents: 250_000, accountID: giro.id, firstPaymentDate: date(2025, 12, 28), dueRule: .lastBusinessDay, dayOfMonth: 28)
            let rent = FixedCost(name: "Miete", amountCents: 80_000, accountID: giro.id, firstChargeDate: date(2026, 1, 1), dayOfMonth: 1)
            let late = FixedCost(name: "Strom", amountCents: 7_000, accountID: giro.id, firstChargeDate: date(2026, 1, 25), dayOfMonth: 25)
            let food = VariableBudget(name: "Essen", monthlyAmountCents: 40_000, accountID: giro.id, createdAt: date(2026, 1, 1))
            let pool = BudgetPool(name: "Freizeit", amountCents: 15_000, accountID: giro.id, createdAt: date(2026, 1, 1))
            [giro, savings, depot].forEach(store.context.insert)
            store.context.insert(salary)
            store.context.insert(rent)
            store.context.insert(late)
            store.context.insert(food)
            store.context.insert(pool)
            store.context.insert(ShoppingItem(name: "Schuhe", amountCents: 9_000, plannedDate: date(2026, 3, 22)))
            store.context.insert(PortfolioHolding(accountID: depot.id, name: "ETF", symbol: "IE00B4L5Y983", quantity: 4, purchasePriceCents: 9_000, currentPriceCents: 11_000))
            IncomeAssignmentStore.setPrimary(iban: outsideIBAN, forecastID: salary.id)
            seedBookings(store, giro: giro, savings: savings, depot: depot, rent: rent, food: food, pool: pool)
            try store.context.save()
            return (giro, salary)
        }

        /// Adds three months of bookings with a split and a refund.
        private func seedBookings(
            _ store: TestStore, giro: Account, savings: Account, depot: Account,
            rent: FixedCost, food: VariableBudget, pool: BudgetPool
        ) {
            store.context.insert(LedgerEntry(date: date(2025, 12, 20), title: "Eröffnungssaldo", amountCents: 150_000, kind: .adjustment, accountID: giro.id))
            for month in 1...3 {
                store.context.insert(LedgerEntry(date: date(2026, month, 1), title: "Miete", amountCents: 80_000, kind: .expense, accountID: giro.id, fixedCostID: rent.id))
                store.context.insert(LedgerEntry(date: date(2026, month, 8), title: "REWE", amountCents: 12_000 + month, kind: .expense, accountID: giro.id, variableBudgetID: food.id))
                if month < 3 {
                    store.context.insert(LedgerEntry(date: date(2026, month, 27), title: "Gehalt", notes: "IBAN: \(outsideIBAN)", amountCents: 250_000, kind: .income, accountID: giro.id))
                }
                store.context.insert(LedgerEntry(date: date(2026, month, 10), title: "Sparen", amountCents: 5_000, kind: .transfer, fromAccountID: giro.id, toAccountID: savings.id))
            }
            let split = LedgerEntry(date: date(2026, 3, 12), title: "Ausflug", amountCents: 6_000, kind: .expense, accountID: giro.id)
            store.context.insert(split)
            store.context.insert(TransactionSplit(transactionID: split.id, targetID: pool.id, kind: .budgetPool, periodKey: CalendarService.periodKey(for: date(2026, 3, 12), pool: pool), amountCents: 4_000))
            let bought = LedgerEntry(date: date(2026, 3, 13), title: "Jacke", amountCents: 5_000, kind: .expense, accountID: giro.id)
            let refund = LedgerEntry(date: date(2026, 3, 15), title: "Erstattung Jacke", amountCents: 2_000, kind: .income, accountID: giro.id)
            store.context.insert(bought)
            store.context.insert(refund)
            RefundLinkStore.link(refundID: refund.id, to: bought.id)
            store.context.insert(LedgerEntry(date: date(2026, 3, 16), title: "Kauf: ETF", amountCents: 9_000, kind: .transfer, fromAccountID: giro.id, toAccountID: depot.id))
        }

        /// Calculates the home budget and all forecast views for past, current, and future periods.
        private func planning() async throws -> [String] {
            try await scenario { store, dump in
                let seeded = try seedPlan(store)
                let accounts = try store.all(Account.self)
                let entries = try store.all(LedgerEntry.self)
                let forecasts = try store.all(IncomeForecast.self)
                let budgets = try store.all(VariableBudget.self)
                let pools = try store.all(BudgetPool.self)
                let splits = try store.all(TransactionSplit.self)
                for mode in DashboardPeriodMode.allCases {
                    let home = HomeBudget.make(entries: entries, accounts: accounts, forecasts: forecasts, variableBudgets: budgets, pools: pools, splits: splits, dashboardPeriod: mode.rawValue, now: now)
                    dump.section("home \(mode.rawValue)", homeRows(home))
                }
                let periods = FinanceService.forecastPeriods(primary: seeded.salary, earliest: date(2025, 12, 20), latest: date(2026, 6, 30))
                let around = periods.filter { $0.end >= date(2026, 2, 1) && $0.start <= date(2026, 5, 1) }
                for period in around {
                    for scope in [nil, seeded.giro] as [Account?] {
                        try forecastRows(period, periods: periods, account: scope, dump: &dump)
                    }
                }
            }
        }

        /// Formats a home budget.
        private func homeRows(_ home: HomeBudgetSnapshot) -> [String] {
            let line = { (kind: String, row: HomeBudgetLine) in "\(kind)|\(row.title)|\(MoneyDump.stamp(row.date))|\(row.cents)" }
            return ["\(home.planned)|\(home.spent)|\(home.remaining)|\(MoneyDump.stamp(home.nextSalary))|\(MoneyDump.stamp(home.periodStart))|\(MoneyDump.stamp(home.periodEnd))|\(home.countsAllExpenses)|\(home.forecastAdjustment)"]
                + home.incomeLines.map { line("income", $0) } + home.forecastLines.map { line("forecast", $0) }
                + home.expenseLines.map { line("expense", $0) } + home.purchaseLines.map { line("purchase", $0) }
                + home.variableLines.map { line("variable", $0) } + home.poolLines.map { line("pool", $0) }
        }

        /// Adds the forecast figures and lists of one period and scope.
        private func forecastRows(_ period: ForecastPeriod, periods: [ForecastPeriod], account: Account?, dump: inout MoneyDump) throws {
            let store = dump.store
            let accounts = try store.all(Account.self)
            let entries = try store.all(LedgerEntry.self)
            let costs = try store.all(FixedCost.self)
            let budgets = try store.all(VariableBudget.self)
            let splits = try store.all(TransactionSplit.self)
            let forecasts = try store.all(IncomeForecast.self)
            let shopping = try store.all(ShoppingItem.self)
            let cash = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }.map(\.id)
            let result = FinanceService.periodForecast(
                period: period, periods: periods, accounts: account.map { [$0] } ?? accounts, entries: entries,
                holdings: try store.all(), fixedCosts: costs, variableBudgets: budgets, splits: splits,
                forecasts: forecasts, shopping: shopping, now: now, includePortfolioValue: account == nil,
                scopedCashAccountIDs: account.map { [$0.id] }, householdCashAccountIDs: cash
            )
            let figures = [result.netWorth, result.income, result.expenses, result.startBalance, result.endBalance, result.remainingFixed, result.remainingVariable, result.biasApplied, result.biasPlanned, result.bookedIncome, result.bookedExpenses, result.bookedFixed, result.bookedVariable, result.openIncome, result.openExpenses]
            let list = ForecastSchedule.financeView(forecasts: forecasts, costs: costs, entries: entries, period: period, account: account, showsDepot: false, budgets: budgets, splits: splits, shopping: shopping, cashAccountIDs: cash)
            dump.section("forecast \(period.id) \(account?.name ?? "all")",
                [figures.map(String.init).joined(separator: "|")]
                    + result.events.map { "event|\(MoneyDump.stamp($0.date))|\($0.title)|\($0.amountCents)" }.sorted()
                    + list.map { "item|\(MoneyDump.stamp($0.date))|\($0.title)|\($0.signedCents)|\($0.settled)" }.sorted())
        }

        @Test func moneyPathsMatchTheReference() async throws {
            var lines: [String] = []
            for (name, part) in [
                ("BANK IMPORT", bankImport), ("STATEMENT", statementImport), ("LIVE SESSION", liveSession),
                ("NOTICES", notices), ("PLANNING", planning), ("BANK LINKS", bankLinks)
            ] as [(String, () async throws -> [String])] {
                lines.append("##### \(name)")
                lines += try await part()
            }
            let text = lines.joined(separator: "\n") + "\n"
            if let path = ProcessInfo.processInfo.environment["LIFIFY_REFERENCE_PATH"] {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                return
            }
            let url = try #require(Bundle(for: ReferenceBundleMarker.self).url(forResource: "money-reference", withExtension: "txt"))
            let expected = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            let actual = text.components(separatedBy: "\n")
            let first = zip(expected, actual).enumerated().first { $0.element.0 != $0.element.1 }
            #expect(first == nil, "Line \((first?.offset ?? 0) + 1): expected \(first?.element.0 ?? ""), got \(first?.element.1 ?? "")")
            #expect(expected.count == actual.count)
        }
    }
}
