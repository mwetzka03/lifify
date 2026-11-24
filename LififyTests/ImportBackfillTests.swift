import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    /// An older export imported after a shorter one adds the missing months without questions.
    @Suite("Import backfill")
    @MainActor
    struct ImportBackfillTests {
        /// A Sparkasse-like CSV with the given rows.
        private func csv(_ rows: [(String, String, String)]) throws -> BankImportDocument {
            let lines = ["Buchungstag;Verwendungszweck;Beguenstigter/Zahlungspflichtiger;Betrag"]
                + rows.map { "\($0.0);\($0.1);\($0.1) GmbH;\($0.2)" }
            return BankImportDocument(rows: try BankImportService.parseCSV(lines.joined(separator: "\n")), tradeRepublic: nil)
        }

        @Test func olderMonthsAreBookedAndTheOpeningMovesBack() async throws {
            try await withTestStore { store in
                FinanceClock.fix(date(2026, 3, 20))
                defer { FinanceClock.fix(nil) }
                let giro = Account(name: "Giro", isMain: true)
                store.context.insert(giro)
                try store.context.save()
                let recent = try csv([("12.03.26", "Miete", "-100,00"), ("15.03.26", "Erstattung", "50,00")])
                _ = try BankImportApplier.apply(document: recent, to: .account(giro.id), currentBalanceCents: 100_000, context: store.context)
                let full = try csv([
                    ("01.03.26", "Bonus", "300,00"), ("05.03.26", "Kino", "-20,00"),
                    ("12.03.26", "Miete", "-100,00"), ("15.03.26", "Erstattung", "50,00")
                ])
                let result = try BankImportApplier.apply(document: full, to: .account(giro.id), currentBalanceCents: 100_000, context: store.context)
                #expect(result.importedCount == 2)
                #expect(result.review.similar.isEmpty)
                let entries: [LedgerEntry] = try store.all()
                let adjustments = entries.filter { $0.kind == .adjustment && $0.accountID == giro.id }
                #expect(adjustments.count == 1)
                let opening = try #require(adjustments.first)
                #expect(Calendar.current.isDate(opening.date, inSameDayAs: date(2026, 3, 1)))
                #expect(opening.amountCents == 105_000 - 28_000)
                #expect(FinanceService.currentBalance(for: giro, entries: entries) == 100_000)
                #expect(entries.filter { $0.accountID == giro.id && $0.kind != .adjustment }.count == 4)
            }
        }

        @Test func daysBeforeTheFirstBookingAreNeverDuplicates() {
            let action = BankImportDuplicates.action(
                day: date(2026, 3, 1), firstExistingDay: date(2026, 3, 12), lastExistingDay: date(2026, 3, 15),
                existingCount: 0, importCount: 3, identical: false, matchedExisting: false
            )
            #expect(action == .ingest)
            let inside = BankImportDuplicates.action(
                day: date(2026, 3, 13), firstExistingDay: date(2026, 3, 12), lastExistingDay: date(2026, 3, 15),
                existingCount: 0, importCount: 1, identical: false, matchedExisting: false
            )
            #expect(inside == .review(include: true))
        }
    }
}
