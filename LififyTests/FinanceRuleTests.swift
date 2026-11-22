import Foundation
import SwiftData
import Testing
@testable import Lifify

extension LififyRuleTests {
    @Suite("Finance balances")
    @MainActor
    struct BalanceTests {
        private let anchorDay = date(2026, 3, 10)

        @Test func balanceStartsAtTheLatestAnchor() {
            let account = Account(name: "Giro")
            let entries = [
                LedgerEntry(date: days(-1, after: anchorDay), title: "Davor", amountCents: -500, kind: .expense, accountID: account.id),
                LedgerEntry(date: anchorDay, title: "Stand", amountCents: 10_000, kind: .adjustment, accountID: account.id),
                LedgerEntry(date: days(1, after: anchorDay), title: "Danach", amountCents: -200, kind: .expense, accountID: account.id)
            ]
            #expect(FinanceService.balance(for: account, entries: entries, holdings: []) == 9_800)
            #expect(FinanceService.balance(for: account, entries: entries, holdings: [], through: anchorDay) == 10_000)
        }

        @Test func transferMovesMoneyBetweenAccounts() {
            let from = Account(name: "Giro")
            let to = Account(name: "Tagesgeld")
            let entries = [LedgerEntry(date: anchorDay, title: "Umbuchung", amountCents: 300, kind: .transfer, fromAccountID: from.id, toAccountID: to.id)]
            #expect(FinanceService.balance(for: from, entries: entries, holdings: []) == -300)
            #expect(FinanceService.balance(for: to, entries: entries, holdings: []) == 300)
            #expect(FinanceService.totalBalance(accounts: [from, to], entries: entries, holdings: []) == 0)
        }

        @Test func totalCountsDepotButNotSavingsGroups() {
            let checking = Account(name: "Giro")
            let depot = Account(name: "Depot", kind: .portfolio)
            let group = Account(name: "Gruppe", kind: .savingsGroup)
            let entries = [
                LedgerEntry(date: anchorDay, title: "Stand", amountCents: 9_800, kind: .adjustment, accountID: checking.id),
                LedgerEntry(date: anchorDay, title: "Gruppe", amountCents: 99_999, kind: .adjustment, accountID: group.id)
            ]
            let holding = PortfolioHolding(accountID: depot.id, name: "Aktie", quantity: 2, purchasePriceCents: 100, currentPriceCents: 150)
            #expect(FinanceService.balance(for: depot, entries: entries, holdings: [holding]) == 300)
            #expect(FinanceService.totalBalance(accounts: [checking, depot, group], entries: entries, holdings: [holding]) == 10_100)
        }
    }

    @Suite("Forecasts")
    @MainActor
    struct ForecastTests {
        @Test func periodsFollowThePrimaryIncomeWithoutGaps() {
            let salary = IncomeForecast(name: "Gehalt", amountCents: 200_000, firstPaymentDate: date(2026, 1, 15), dayOfMonth: 15)
            let periods = FinanceService.forecastPeriods(primary: salary, earliest: date(2026, 2, 1), latest: date(2026, 4, 30))
            #expect(periods.count >= 3)
            for (current, next) in zip(periods, periods.dropFirst()) {
                #expect(days(1, after: current.end) == next.start)
            }
            #expect(periods.dropFirst().allSatisfy { Calendar.current.component(.day, from: $0.start) == 15 })
        }

        @Test func forecastAddsPlannedIncomeAndFixedCosts() async throws {
            try await withTestStore { _ in
                let account = Account(name: "Giro")
                let anchor = LedgerEntry(date: date(2026, 2, 28), title: "Stand", amountCents: 100_000, kind: .adjustment, accountID: account.id)
                let salary = IncomeForecast(name: "Gehalt", amountCents: 200_000, accountID: account.id, firstPaymentDate: date(2026, 1, 15), dayOfMonth: 15)
                let rent = FixedCost(name: "Miete", amountCents: 50_000, accountID: account.id, firstChargeDate: date(2026, 1, 20), dayOfMonth: 20)
                let period = ForecastPeriod(
                    start: Calendar.current.startOfDay(for: date(2026, 3, 1)),
                    end: Calendar.current.startOfDay(for: date(2026, 3, 31))
                )
                let result = FinanceService.periodForecast(
                    period: period,
                    periods: [period],
                    accounts: [account],
                    entries: [anchor],
                    holdings: [],
                    fixedCosts: [rent],
                    variableBudgets: [],
                    splits: [],
                    forecasts: [salary],
                    shopping: [],
                    now: date(2026, 3, 10)
                )
                #expect(result.startBalance == 100_000)
                #expect(result.income == 200_000)
                #expect(result.remainingFixed == 50_000)
                #expect(result.endBalance == 250_000)
            }
        }
    }

    @Suite("Depot and savings plans")
    @MainActor
    struct PortfolioTests {
        private func plan(depot: UUID, holding: UUID?, amount: Int = 10_000) -> SavingsPlanRecord {
            SavingsPlanRecord(
                id: UUID(),
                isin: "IE00B4L5Y983",
                name: "World",
                amountCents: amount,
                cadenceRaw: Cadence.monthly.rawValue,
                checkingAccountID: UUID(),
                portfolioAccountID: depot,
                holdingID: holding,
                lastExecution: .now,
                historyThrough: .now,
                active: true
            )
        }

        private func executions(through target: Date) -> Int {
            let tomorrow = days(1, after: Calendar.current.startOfDay(for: .now))
            return CalendarService.savingsPlanDates(cadence: .monthly, from: tomorrow, through: target).count
        }

        @Test func futureExecutionsBuyAtTheCurrentPrice() async throws {
            try await withTestStore { _ in
                let depot = UUID()
                let holding = PortfolioHolding(accountID: depot, name: "World", symbol: "IE00B4L5Y983", quantity: 2, purchasePriceCents: 4_000, currentPriceCents: 5_000)
                SavingsPlanStore.upsert(plan(depot: depot, holding: holding.id))
                let target = days(100, after: .now)
                let count = executions(through: target)
                #expect(count > 0)
                let quantity = HoldingMaintenance.quantity(of: holding, through: target, holdings: [holding])
                #expect(abs(quantity - Double(2 + 2 * count)) < 0.000001)
                #expect(HoldingMaintenance.marketValue(of: [holding], through: target) == (2 + 2 * count) * 5_000)
                #expect(HoldingMaintenance.quantity(of: holding, through: .now, holdings: [holding]) == 2)
            }
        }

        @Test func planWithoutPricedHoldingAddsItsNominalAmount() async throws {
            try await withTestStore { _ in
                SavingsPlanStore.upsert(plan(depot: UUID(), holding: nil, amount: 2_500))
                let target = days(100, after: .now)
                #expect(HoldingMaintenance.marketValue(of: [], through: target) == executions(through: target) * 2_500)
            }
        }

        @Test func averagePriceFollowsLots() throws {
            let day = date(2026, 3, 2)
            let lots = [
                HoldingLot(date: day, quantity: 2, unitPriceCents: 500, amountCents: -1_000, isSale: false, isSavingsPlan: false),
                HoldingLot(date: days(1, after: day), quantity: 1, unitPriceCents: 700, amountCents: 700, isSale: true, isSavingsPlan: false),
                HoldingLot(date: days(2, after: day), quantity: 1, unitPriceCents: 900, amountCents: 0, isSale: false, isSavingsPlan: false, source: "gift")
            ]
            let position = try #require(HoldingMaintenance.averagePurchaseCents(for: lots))
            #expect(position.quantity == 2)
            #expect(position.priceCents == 250)
        }

        @Test func fullySoldPositionCloses() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let holding = PortfolioHolding(name: "Apple", symbol: "US0378331005", quantity: 2, purchasePriceCents: 500, currentPriceCents: 600)
                store.context.insert(holding)
                HoldingLotStore.replace([
                    HoldingLot(date: day, quantity: 2, unitPriceCents: 500, amountCents: -1_000, isSale: false, isSavingsPlan: false),
                    HoldingLot(date: days(1, after: day), quantity: 2, unitPriceCents: 900, amountCents: 1_800, isSale: true, isSavingsPlan: false)
                ], holdingID: holding.id)
                #expect(!HoldingMaintenance.sync(holding, context: store.context))
                try #expect(store.all(PortfolioHolding.self).isEmpty)
                #expect(ClosedPositionStore.all().count == 1)
            }
        }

        @Test func saleWithoutLivePositionIsBookedAndLotsCloseIt() {
            let sale = TradeRepublicActivity(id: "sale", date: date(2026, 3, 3), title: "Apple", eventType: "ORDER_EXECUTED", amountCents: 1_800, isin: "US0378331005", trade: true, status: "EXECUTED")
            let held = HeldPosition(symbol: "US0378331005", name: "Apple", quantity: 2, purchasePriceCents: 500, latestLotDate: nil)
            let moves = TradeRepublicSync.changes(positions: [], holdings: [held], activities: [sale], known: [])
            #expect(moves.contains { if case .sale(_, _, _, _, _, let quantity, let amount) = $0 { return quantity == 2 && amount == 1_800 }; return false })
            #expect(!moves.contains { if case .drop = $0 { return true }; return false })
        }

        @Test func buyWithoutShareCountUsesTheAveragePrice() {
            let buy = TradeRepublicActivity(id: "buy", date: date(2026, 3, 3), title: "World", eventType: "ORDER_EXECUTED", amountCents: -4_000, isin: "IE00B4L5Y983", trade: true, status: "EXECUTED")
            let held = HeldPosition(symbol: "IE00B4L5Y983", name: "World", quantity: 4, purchasePriceCents: 1_000, latestLotDate: nil)
            let position = TradeRepublicPosition(isin: "IE00B4L5Y983", name: "World", quantity: 8, averageBuyInCents: 1_000)
            let moves = TradeRepublicSync.changes(positions: [position], holdings: [held], activities: [buy], known: [])
            #expect(moves.contains { if case .buy(_, _, _, _, _, let quantity, _, _) = $0 { return abs(quantity - 4) < 0.000001 }; return false })
        }

        @Test func cryptoIdentifierStaysQuoteable() {
            #expect(MarketDataService.cryptoTicker(from: "XF000BTC0017") == "BTC")
            #expect(MarketDataService.isQuoteable("XF000BTC0017"))
        }
    }

    @Suite("Bank import")
    struct BankImportTests {
        @Test func sameDaySameAmountTwinsStayApart() throws {
            let csv = """
            Buchungstag;Betrag;Verwendungszweck;Beguenstigter/Zahlungspflichtiger;Kontonummer/IBAN;Kundenreferenz (End-to-End);Info
            03.11.26;-38,80;1054118451739;PayPal Europe;DE89370400440532013000;1054118451739;Umsatz gebucht
            03.11.26;-38,80;1054124404910;PayPal Europe;DE89370400440532013000;1054124404910;Umsatz gebucht
            16.11.26;-9,05;Steam;Steam;DE89370400440532013000;steam-1;Umsatz vorgemerkt
            """
            let rows = try BankImportService.parseCSV(csv)
            #expect(rows.count == 2)
            #expect(rows[0].fingerprint != rows[1].fingerprint)
            #expect(rows[0].legacyFingerprint != rows[1].legacyFingerprint)
        }
    }

    @Suite("Backup round trip")
    @MainActor
    struct BackupTests {
        private func export(_ store: TestStore, scope: BackupScope) throws -> Data {
            try BackupService.exportData(
                accounts: store.all(),
                entries: store.all(),
                splits: store.all(),
                fixedCosts: store.all(),
                variableBudgets: store.all(),
                pools: store.all(),
                forecasts: store.all(),
                shopping: store.all(),
                debts: store.all(),
                groups: store.all(),
                lines: store.all(),
                holdings: store.all(),
                calendarEvents: store.all(),
                challenges: store.all(),
                completions: store.all(),
                challengeGroups: store.all(),
                coinTransactions: store.all(),
                rewards: store.all(),
                purchases: store.all(),
                bucketItems: store.all(),
                scope: scope
            )
        }

        @Test func financeSurvivesExportAndRestore() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let account = Account(name: "Giro", isMain: true)
                let depot = Account(name: "Depot", kind: .portfolio)
                let entry = LedgerEntry(date: day, title: "Stand", amountCents: 12_345, kind: .adjustment, accountID: account.id)
                let holding = PortfolioHolding(accountID: depot.id, name: "World", symbol: "IE00B4L5Y983", quantity: 2, purchasePriceCents: 500, currentPriceCents: 600)
                [account, depot].forEach(store.context.insert)
                store.context.insert(entry)
                store.context.insert(holding)
                let lot = HoldingLot(date: day, quantity: 2, unitPriceCents: 500, amountCents: -1_000, isSale: false, isSavingsPlan: false)
                HoldingLotStore.replace([lot], holdingID: holding.id)
                let holdingID = holding.id
                try store.context.save()

                let data = try export(store, scope: .finance)
                store.context.delete(entry)
                store.context.delete(holding)
                HoldingLotStore.reset()
                try store.context.save()
                try BackupService.restore(data: data, into: store.context)
                try store.context.save()

                let entries: [LedgerEntry] = try store.all()
                #expect(entries.map(\.amountCents) == [12_345])
                try #expect(store.all(PortfolioHolding.self).map(\.id) == [holdingID])
                #expect(HoldingLotStore.lots(for: holdingID) == [lot])
            }
        }

        @Test func challengesSurviveExportAndRestore() async throws {
            try await withTestStore { store in
                let day = date(2026, 3, 2)
                let challenge = ChallengeItem(title: "Lesen", category: .todo, startDate: day, rewardCoins: 10)
                let completion = ChallengeCompletion(challengeID: challenge.id, date: day, earnedCoins: 10)
                let event = ChallengeCalendarEvent(title: "Termin", startDate: day, endDate: day.addingTimeInterval(3_600))
                let plan = UUID()
                store.context.insert(challenge)
                store.context.insert(completion)
                store.context.insert(event)
                store.context.insert(CoinTransaction(title: "Lesen", amount: 10, referenceID: completion.id))
                StreakSettings.setEnabled(true, for: challenge.id)
                StreakSettings.addPurchasedFreeze(for: challenge.id)
                ChallengeTimeStore.setMinutes(45, for: challenge.id)
                ChallengeTimeStore.setMembers([challenge.id], for: event.id)
                WorkoutLinkStore.link(planID: plan, challengeID: challenge.id)
                let challengeID = challenge.id
                let eventID = event.id
                try store.context.save()

                let data = try export(store, scope: .challenges)
                store.context.delete(completion)
                StreakSettings.reset()
                ChallengeTimeStore.reset()
                WorkoutLinkStore.reset()
                try store.context.save()
                try BackupService.restore(data: data, into: store.context)
                try store.context.save()

                try #expect(store.wallet() == 10)
                try #expect(store.all(ChallengeCompletion.self).count == 1)
                #expect(StreakSettings.state(for: challengeID)?.purchased == 1)
                #expect(ChallengeTimeStore.minutes(for: challengeID) == 45)
                #expect(ChallengeTimeStore.memberIDs(for: eventID) == [challengeID])
                #expect(WorkoutLinkStore.planIDs(forChallenge: challengeID) == [plan])
            }
        }
    }
}
