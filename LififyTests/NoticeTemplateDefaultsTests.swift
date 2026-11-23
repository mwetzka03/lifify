import Foundation
import LififyChallenges
import LififyCore
import LififyFinance
import LififyHealth
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Built-in notice templates")
    @MainActor
    struct NoticeTemplateDefaultsTests {
        private let sparkasse = NamedAccount(id: UUID(), name: "Sparkasse", kind: .checking, isMain: true)
        private let trade = NamedAccount(id: UUID(), name: "Trade Republic", kind: .checking, isMain: false)
        private let depot = NamedAccount(id: UUID(), name: "Depot", kind: .portfolio, isMain: false)
        private let now = date(2026, 11, 23)

        private var accounts: [NamedAccount] { [sparkasse, trade, depot] }

        private func plan(_ text: String, _ bank: BankNoticeBank, existing: [BookedNotice] = []) -> BankNoticePlan {
            BankNotice.plan(
                text: text,
                bank: bank,
                accounts: accounts,
                existing: existing,
                now: now,
                templates: NoticeTemplateDefaults.install(accounts: accounts)
            )
        }

        @Test func sparkasseDebitReadsMerchantAndIgnoresBalance() async throws {
            try await withTestStore { _ in
                let result = plan("Konto 1234567890:\nSoundClou.: -19,99 EUR\nNeuer Saldo: 2.362,92 EUR", .sparkasse)
                #expect(result == .book(accountID: sparkasse.id, title: "SoundClou", amountCents: -1_999, kind: .expense))
            }
        }

        @Test func sparkasseAmountWithoutMinusIsACredit() async throws {
            try await withTestStore { _ in
                let result = plan("Konto 1234567890:\nPAYPAL: 27,32 EUR\nNeuer Saldo: 1.921,42 EUR", .sparkasse)
                #expect(result == .book(accountID: sparkasse.id, title: "PAYPAL", amountCents: 2_732, kind: .income))
            }
        }

        @Test func dividendBooksTheEuroAmountAsIncome() async throws {
            try await withTestStore { _ in
                let text = "Apple hat heute eine Dividende von 0,27 $ pro Aktie ausgeschüttet. Du hast 0,01 € erhalten."
                #expect(plan(text, .tradeRepublic) == .bookNoted(
                    accountID: trade.id, title: "Dividende: Apple", amountCents: 1, kind: .income, notes: "Typ: Ertrag"
                ))
            }
        }

        @Test(arguments: [
            ("Dein MSCI World Ex-USA USD (Acc) Sparplan von 45,00 € wurde ausgeführt", "Sparplan: MSCI World Ex-USA USD (Acc)", 4_500),
            ("Deine Kauf Order von 2 × NVIDIA wurde für 283,24 € ausgeführt.", "Kauf: NVIDIA", 28_324),
            ("Deine Kauf Order von 5.109114 × MSCI World Ex-USA USD (Acc) wurde für 199,00 € ausgeführt.", "Kauf: MSCI World Ex-USA USD (Acc)", 19_900),
            ("Deine Kauf Order von 0.589796 × MSCI USA USD (Acc) wurde für 399,99 € ausgeführt.", "Kauf: MSCI USA USD (Acc)", 39_999),
            ("Deine Kauf Order von 200 × Short 144,7 $ wurde für 108,00 € ausgeführt.", "Kauf: Short 144,7 $", 10_800)
        ])
        func purchasesMoveCashIntoTheDepot(text: String, title: String, cents: Int) async throws {
            try await withTestStore { _ in
                #expect(plan(text, .tradeRepublic) == .bookTransfer(
                    fromAccountID: trade.id, toAccountID: depot.id, title: title, amountCents: cents
                ))
            }
        }

        @Test func saleMovesCashOutOfTheDepot() async throws {
            try await withTestStore { _ in
                let text = "Deine Verkaufen Order von 200 × Short 144,7 $ wurde für 90,00 € ausgeführt."
                #expect(plan(text, .tradeRepublic) == .bookTransfer(
                    fromAccountID: depot.id, toAccountID: trade.id, title: "Verkauf: Short 144,7 $", amountCents: 9_000
                ))
            }
        }

        @Test func cardPaymentIsAnExpense() async throws {
            try await withTestStore { _ in
                #expect(plan("15,90 € bei Lieferando ausgegeben", .tradeRepublic) == .book(
                    accountID: trade.id, title: "Lieferando", amountCents: -1_590, kind: .expense
                ))
            }
        }

        @Test(arguments: [
            "Deine Limit Kauf Order von 3 × NVIDIA wurde storniert.",
            "Deine Trailing Stop Verkaufen Order von 12 × MSCI USA Daily (2x) Leveraged EUR (Acc) wurde storniert."
        ])
        func cancelledOrdersBookNothing(text: String) async throws {
            try await withTestStore { _ in
                #expect(plan(text, .tradeRepublic) == .ignored)
            }
        }

        @Test func sameAmountForAnotherStockIsNoDuplicate() async throws {
            try await withTestStore { _ in
                let apple = "Apple hat heute eine Dividende von 0,27 $ pro Aktie ausgeschüttet. Du hast 0,01 € erhalten."
                let other = "Microsoft hat heute eine Dividende von 0,83 $ pro Aktie ausgeschüttet. Du hast 0,01 € erhalten."
                let booked = BookedNotice(accountID: trade.id, amountCents: 1, direction: .in, date: now, title: "Dividende: Apple")
                #expect(plan(apple, .tradeRepublic, existing: [booked]) == .duplicate)
                if case .bookNoted = plan(other, .tradeRepublic, existing: [booked]) {} else {
                    Issue.record("Another stock must be booked")
                }
            }
        }

        @Test func everyExampleMatchesOnlyItsOwnFormat() {
            for format in NoticeFormat.allCases {
                #expect(NoticeFormat.allCases.filter { $0.matches(format.example) } == [format])
            }
        }

        @Test func disabledTemplateIsSkipped() async throws {
            try await withTestStore { _ in
                var templates = NoticeTemplateDefaults.install(accounts: accounts)
                let index = try #require(templates.firstIndex { $0.format == .cancelledOrder })
                templates[index].isEnabled = false
                let result = BankNotice.plan(
                    text: "Deine Limit Kauf Order von 3 × NVIDIA wurde storniert.",
                    bank: .tradeRepublic,
                    accounts: accounts,
                    existing: [],
                    now: now,
                    templates: templates
                )
                #expect(result == .unreadable)
            }
        }

        @Test func ownTemplateWinsOverABuiltInOne() async throws {
            try await withTestStore { _ in
                let own = NoticeTemplate(accountID: trade.id, name: "Eigen", example: "10,00 € bei X ausgegeben", action: .income)
                let templates = NoticeTemplateDefaults.install(accounts: accounts) + [own]
                let result = BankNotice.plan(text: "15,90 € bei Lieferando ausgegeben", bank: .tradeRepublic, accounts: accounts, existing: [], now: now, templates: templates)
                if case .book(_, _, let cents, let kind) = result {
                    #expect(cents == 1_590)
                    #expect(kind == .income)
                } else {
                    Issue.record("Expected a booking")
                }
            }
        }

        @Test func installIsIdempotentAndDeletedStaysDeleted() async throws {
            try await withTestStore { _ in
                let first = NoticeTemplateDefaults.install(accounts: accounts)
                #expect(first.count == NoticeFormat.allCases.count)
                #expect(NoticeTemplateDefaults.install(accounts: accounts).count == first.count)
                let target = try #require(first.first { $0.format == .dividend })
                _ = NoticeTemplateDefaults.delete([target.id], from: first)
                let again = NoticeTemplateDefaults.install(accounts: accounts)
                #expect(again.count == first.count - 1)
                #expect(!again.contains { $0.format == .dividend })
            }
        }

        @Test func missingAccountGetsNoTemplateUntilItExists() async throws {
            try await withTestStore { _ in
                let only = NoticeTemplateDefaults.install(accounts: [sparkasse])
                #expect(Set(only.compactMap(\.format)) == [.sparkasseDebit, .sparkasseCredit])
                #expect(NoticeTemplateDefaults.install(accounts: accounts).count == NoticeFormat.allCases.count)
            }
        }

        @Test func editedExampleBecomesAnOwnTemplate() async throws {
            try await withTestStore { _ in
                var template = try #require(NoticeTemplateDefaults.install(accounts: accounts).first { $0.format == .cardPayment })
                template.example = "Abbuchung 5,00 EUR Test"
                #expect(NoticeTemplateDefaults.detachedIfEdited(template).format == nil)
                let templates = NoticeTemplateDefaults.install(accounts: accounts)
                #expect(!templates.contains { $0.format == .cardPayment && $0.id != template.id })
            }
        }

        @Test func olderStoredTemplateStaysEnabled() throws {
            let old = #"{"id":"11111111-1111-1111-1111-111111111111","accountID":"22222222-2222-2222-2222-222222222222","name":"Alt","example":"Abbuchung 1,00 EUR","action":"expense"}"#
            let decoded = try JSONDecoder().decode(NoticeTemplate.self, from: Data(old.utf8))
            #expect(decoded.isEnabled)
            #expect(decoded.format == nil)
        }

        @Test func stateSurvivesBackup() async throws {
            try await withTestStore { store in
                var templates = NoticeTemplateDefaults.install(accounts: accounts)
                let index = try #require(templates.firstIndex { $0.format == .tradeBuy })
                templates[index].isEnabled = false
                NoticeTemplateStore.save(templates)
                let deleted = try #require(templates.first { $0.format == .dividend })
                _ = NoticeTemplateDefaults.delete([deleted.id], from: templates)
                let data = try BackupService.exportData(
                    accounts: [], entries: [], splits: [], fixedCosts: [], variableBudgets: [], pools: [],
                    forecasts: [], shopping: [], debts: [], groups: [], lines: [], holdings: [],
                    calendarEvents: [], challenges: [], completions: [], challengeGroups: [],
                    coinTransactions: [], rewards: [], purchases: [], bucketItems: [],
                    scope: .finance
                )
                try BackupService.deleteFinanceData(from: store.context)
                try BackupService.restore(data: data, into: store.context)
                let restored = NoticeTemplateDefaults.install(accounts: accounts)
                #expect(restored.first { $0.format == .tradeBuy }?.isEnabled == false)
                #expect(!restored.contains { $0.format == .dividend })
            }
        }
    }
}
