import Foundation
import LififyCore
import LififyFinance
import SwiftData
import Testing

extension LififyRuleTests {
    /// A bank import fills in notice bookings, and PayPal bookings are named after their real payee.
    @Suite("Notice import and PayPal")
    @MainActor
    struct NoticeImportTests {
        private let paypalNotes = """
        Buchungstext: FOLGELASTSCHRIFT
        Verwendungszweck: 1053648549815/PP.2481.PP/. Netflix.com, Ihr Einkauf bei Netflix.com
        Gegenpartei: PayPal Europe S.a.r.l. et Cie S.C.A
        Empfänger-IBAN: LU89751000135104200E
        """

        @Test func payPalBookingsTakeTheRealPayee() async throws {
            try await withTestStore { _ in
                #expect(PayPalBookings.payee(in: paypalNotes) == "Netflix.com")
                #expect(PayPalBookings.title(for: "PayPal Europe S.a.r.l. et Cie S.C.A", notes: paypalNotes) == "Netflix.com (PayPal)")
                let empty = "Verwendungszweck: 1053726380106/PP.2481.PP/. , Ihr Einkauf bei\nGegenpartei: PayPal Europe"
                #expect(PayPalBookings.payee(in: empty) == nil)
                #expect(PayPalBookings.title(for: "PayPal Europe S.a.r.l. et Cie S.C.A", notes: empty) == "PayPal")
                #expect(PayPalBookings.title(for: "REWE", notes: "Verwendungszweck: Einkauf") == "REWE")

                let netflix = LedgerEntry(title: "PayPal Europe S.a.r.l. et Cie S.C.A", notes: paypalNotes, amountCents: -1_099, kind: .expense)
                let renamedByHand = LedgerEntry(title: "Abo", notes: paypalNotes, amountCents: -1_099, kind: .expense)
                #expect(PayPalBookings.rename([netflix, renamedByHand]) == 1)
                #expect(netflix.title == "Netflix.com (PayPal)")
                #expect(renamedByHand.title == "Abo")
                // Rules and fixed costs follow the payee, not PayPal's shared IBAN.
                #expect(BudgetPayeeRules.rule(from: netflix) == "Netflix.com")
                #expect(FixedCostFromBooking.payeeKey(of: netflix) == "payee:netflixcom")
            }
        }

        @Test func anImportFillsInTheNoticeBookingAndKeepsItsAssignments() async throws {
            try await withTestStore { store in
                let giro = Account(name: "Sparkasse Giro", isMain: true)
                store.context.insert(giro)
                let food = VariableBudget(name: "Lebensmittel", monthlyAmountCents: 40_000)
                store.context.insert(food)
                try store.context.save()
                BankNoticeIntake.commit(
                    text: "Du hast 12,50 € bei Bäckerei Müller ausgegeben",
                    bank: .sparkasse,
                    context: store.context,
                    now: date(2026, 3, 5, 12)
                )
                let notice = try #require(try store.context.fetch(FetchDescriptor<LedgerEntry>()).first)
                #expect(NoticeBookings.isNotice(notice.id))
                notice.variableBudgetID = food.id
                try store.context.save()

                let row = BankImportService.imported(
                    date: date(2026, 3, 5), title: "Bäckerei Müller GmbH", amount: -1_250, senderIBAN: "", recipientIBAN: "",
                    legacyIBAN: "", legacyTitle: "Bäckerei Müller GmbH", details: "Verwendungszweck: Kartenzahlung", trade: nil, distinct: "x"
                )
                let other = BankImportService.imported(
                    date: date(2026, 3, 5), title: "Aral", amount: -1_250, senderIBAN: "", recipientIBAN: "",
                    legacyIBAN: "", legacyTitle: "Aral", details: "", trade: nil, distinct: "y"
                )
                _ = try BankImportApplier.apply(
                    document: BankImportDocument(rows: [row, other], tradeRepublic: nil),
                    to: .account(giro.id),
                    detectDuplicates: false,
                    context: store.context
                )
                let entries = try store.context.fetch(FetchDescriptor<LedgerEntry>()).filter { $0.amountCents == -1_250 }
                let filled = try #require(entries.first { $0.id == notice.id })
                #expect(filled.title == "Bäckerei Müller GmbH")
                #expect(filled.importFingerprint == row.fingerprint)
                #expect(filled.variableBudgetID == food.id)
                #expect(!NoticeBookings.isNotice(notice.id))
                #expect(entries.count == 2)
                #expect(LinkKind.financeRecords.contains(.noticeBooking))
            }
        }
    }
}
