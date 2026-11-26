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

        private let payPalCSV = """
        "Datum","Uhrzeit","Zeitzone","Name","Typ","Status","Währung","Brutto","Gebühr","Netto","Absender E-Mail-Adresse","Transaktionscode"
        "02.03.2026","10:15:00","Europe/Berlin","Netflix.com","Allgemeine Zahlung","Abgeschlossen","EUR","-10,99","0,00","-10,99","me@example.com","4AB12345CD"
        "02.03.2026","10:15:00","Europe/Berlin","","Bankgutschrift auf PayPal-Konto","Abgeschlossen","EUR","10,99","0,00","10,99","","5CD67890EF"
        "03.03.2026","08:00:00","Europe/Berlin","Shop USA","Allgemeine Zahlung","Abgeschlossen","USD","-5,00","0,00","-5,00","me@example.com","6EF00000GH"
        "04.03.2026","09:00:00","Europe/Berlin","Max Muster","Allgemeine Zahlung","Ausstehend","EUR","-3,00","0,00","-3,00","me@example.com","7GH11111IJ"
        """

        @Test func aPayPalExportBooksPaymentsOnlyAndPairsTheBankDebit() async throws {
            try await withTestStore { store in
                let giro = Account(name: "Sparkasse Giro", isMain: true)
                store.context.insert(giro)
                let food = VariableBudget(name: "Abos", monthlyAmountCents: 5_000)
                store.context.insert(food)
                let debit = LedgerEntry(
                    date: date(2026, 3, 4), title: "PayPal Europe S.a.r.l. et Cie S.C.A", notes: paypalNotes,
                    amountCents: -1_099, kind: .expense, accountID: giro.id, variableBudgetID: food.id
                )
                store.context.insert(debit)
                try store.context.save()

                let rows = try #require(PayPalCSV.parse(payPalCSV))
                #expect(rows.map(\.title) == ["Netflix.com"])
                #expect(rows.first?.amountCents == -1_099)
                let document = try BankImportService.parseDocument(data: Data(payPalCSV.utf8), fileExtension: "csv")
                #expect(document.isPayPal)
                _ = try BankImportApplier.apply(document: document, to: .separateChecking, context: store.context)

                let accounts = try store.context.fetch(FetchDescriptor<Account>())
                let payPal = try #require(PayPalAccount.find(in: accounts))
                let entries = try store.context.fetch(FetchDescriptor<LedgerEntry>())
                let payment = try #require(entries.first { $0.accountID == payPal.id })
                #expect(payment.title == "Netflix.com")
                #expect(payment.variableBudgetID == food.id)
                #expect(debit.kind == .transfer)
                #expect(debit.fromAccountID == giro.id && debit.toAccountID == payPal.id)
                #expect(debit.variableBudgetID == nil)
                #expect(PayPalAccount.pairDebits(context: store.context) == 0)
                #expect(LinkKind.financeRecords.contains(.payPalPairing))
            }
        }

        @Test func aPayPalMailBooksOnThePayPalAccount() async throws {
            try await withTestStore { store in
                #expect(PayPalMail.parse("Sie haben eine Zahlung über 10,99 € EUR an Netflix.com gesendet.")?.title == "Netflix.com")
                #expect(PayPalMail.parse("Sie haben eine Zahlung über 10,99 € EUR an Netflix.com gesendet.")?.amountCents == -1_099)
                #expect(PayPalMail.parse("You sent a payment of €1,234.50 EUR to Shop Ltd.")?.amountCents == -123_450)
                let received = PayPalMail.parse("Sie haben 20,00 € EUR von Max Muster erhalten")
                #expect(received?.direction == .in && received?.title == "Max Muster")
                #expect(PayPalMail.parse("Ihr Konto wurde aktualisiert") == nil)

                store.context.insert(Account(name: "Sparkasse Giro", isMain: true))
                try store.context.save()
                BankNoticeIntake.commit(text: "Sie haben eine Zahlung über 10,99 € EUR an Netflix.com gesendet", bank: .paypal, context: store.context)
                let accounts = try store.context.fetch(FetchDescriptor<Account>())
                let payPal = try #require(PayPalAccount.find(in: accounts))
                let entry = try #require(try store.context.fetch(FetchDescriptor<LedgerEntry>()).first)
                #expect(entry.accountID == payPal.id && entry.amountCents == -1_099 && entry.title == "Netflix.com")
                #expect(BankNoticeURL.decode(URL(string: "lifify://notice?account=paypal&text=x")!)?.bank == .paypal)
            }
        }
    }
}

