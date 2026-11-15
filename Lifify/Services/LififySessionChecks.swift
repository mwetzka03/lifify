import Foundation
import Security

/// Checks for the Trade Republic session and the bank-notice shortcut.
/// They use values in memory and do not write the user's data.
@MainActor
enum LififySessionChecks {
    static func run() -> [LififyCheckResult] {
        [
            noticeReadsAmountDirectionAndTitle(),
            sameBookingInsideTheWindowCountsOnce(),
            depotSetsQuantityAndCostAndInventsNothing(),
            deadSessionDoesNotStartAnotherLogin(),
            sparkasseAndTradeRepublicLandOnTheMatchingAccount(),
            signInAndRefreshStayManual()
        ]
    }

    private static func noticeReadsAmountDirectionAndTitle() -> LififyCheckResult {
        let debit = BankNotice.parse("Abbuchung 12,34 EUR REWE", fallbackTitle: "Sparkasse")
        let credit = BankNotice.parse("Gutschrift +1.250,00 € Gehalt", fallbackTitle: "Sparkasse")
        let bare = BankNotice.parse("12,34 EUR", fallbackTitle: "Sparkasse")
        let paid = BankNotice.parse("You paid €8.90 at Baker", fallbackTitle: "Sparkasse")
        let received = BankNotice.parse("Received 15.00 EUR from Alex", fallbackTitle: "Sparkasse")
        let spent = BankNotice.parse("10,00 € bei Tabakwaren Dietz ausgegeben", fallbackTitle: "Trade Republic")
        let wire = BankNotice.parse(
            "Überweisung erhalten\nDu hast 2.000,00 € von Someone erhalten",
            fallbackTitle: "Trade Republic"
        )
        let pin = String(repeating: "0", count: 4)
        let body = TradeRepublicRequest.body(phone: "+490000", pin: pin)
        let fields = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let passed = debit?.amountCents == -1234
            && debit?.direction == .out
            && debit?.title == "REWE"
            && credit?.amountCents == 125000
            && credit?.direction == .in
            && credit?.title == "Gehalt"
            && bare == nil
            && paid?.amountCents == -890
            && paid?.direction == .out
            && paid?.title == "You at Baker"
            && received?.amountCents == 1500
            && received?.direction == .in
            && received?.title == "from Alex"
            && spent?.amountCents == -1000
            && spent?.direction == .out
            && spent?.title == "Tabakwaren Dietz"
            && wire?.amountCents == 200_000
            && wire?.direction == .in
            && (fields["phoneNumber"] as? String) == "+490000"
            && (fields["pin"] as? String) == pin
            && fields.count == 2
        let reading = "\(debit?.amountCents ?? 0), aus, \(debit?.title ?? ""), \(credit?.amountCents ?? 0), ein, \(credit?.title ?? ""), \(bare == nil ? "ungelesen" : "gelesen")"
        return result("Eine Mitteilung nennt Betrag, Richtung und Titel", .bankImport, .unit, passed, reading)
    }

    private static func sameBookingInsideTheWindowCountsOnce() -> LififyCheckResult {
        let account = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        guard let notice = BankNotice.parse("Abbuchung 4,20 EUR REWE", fallbackTitle: "Sparkasse") else {
            return result("Dieselbe Buchung im kurzen Fenster zählt einmal", .bankImport, .unit, false, "ungelesen")
        }
        let recent = BookedNotice(accountID: account, amountCents: -420, direction: .out, date: now.addingTimeInterval(-3600))
        let income = ParsedNotice(amountCents: 420, title: "REWE", direction: .in)
        let later = BookedNotice(accountID: account, amountCents: -420, direction: .out, date: now.addingTimeInterval(-(7 * 3600)))
        let duplicate = BankNotice.isDuplicate(notice, accountID: account, existing: [recent], now: now)
        let otherDirection = BankNotice.isDuplicate(income, accountID: account, existing: [recent], now: now)
        let afterWindow = BankNotice.isDuplicate(notice, accountID: account, existing: [later], now: now)
        let passed = BankNotice.duplicateWindow == 6 * 60 * 60
            && duplicate
            && !otherDirection
            && !afterWindow
            && notice.amountCents == -420
        let reading = duplicate ? "6h duplicate" : "6h new"
        return result("Dieselbe Buchung im kurzen Fenster zählt einmal", .bankImport, .unit, passed, reading)
    }

    private static func depotSetsQuantityAndCostAndInventsNothing() -> LififyCheckResult {
        let payload = #"{"categories":[{"positions":[{"isin":"IE00B4L5Y983","name":"World","netSize":2.5,"averageBuyIn":80}]}]}"#
        let read = TradeRepublicPortfolio.read(Data(payload.utf8))
        let position: TradeRepublicPosition?
        if case .positions(let rows) = read, rows.count == 1 {
            position = rows[0]
        } else {
            position = nil
        }
        let created = TradeRepublicDepotPlan.edits(
            positions: position.map { [$0] } ?? [],
            holdings: []
        )
        let kept = TradeRepublicDepotPlan.edits(
            positions: [TradeRepublicPosition(isin: "IE00B4L5Y983", name: "", quantity: 1, averageBuyInCents: nil)],
            holdings: [HoldingSeed(symbol: "ie00b4l5y983", name: "World", quantity: 2, purchasePriceCents: 1000)]
        )
        let empty = TradeRepublicDepotPlan.edits(positions: [], holdings: [])
        let blank = TradeRepublicPortfolio.read(Data(#"{"categories":[]}"#.utf8))
        let broken = TradeRepublicPortfolio.read(Data(#"{"foo":1}"#.utf8))
        let one = NamedAccount(id: UUID(), name: "Depot", kind: .portfolio, isMain: false)
        let other = NamedAccount(id: UUID(), name: "Weiteres", kind: .portfolio, isMain: false)
        let passed = position?.quantity == 2.5
            && position?.averageBuyInCents == 8000
            && position?.isin == "IE00B4L5Y983"
            && created.count == 1
            && created.first?.isNew == true
            && kept.first?.purchasePriceCents == 1000
            && kept.first?.quantity == 1
            && kept.first?.name == "World"
            && empty.isEmpty
            && blank == .positions([])
            && broken == .unreadable
            && TradeRepublicDepotTarget.choose(accounts: [one], linkedPortfolioID: nil) == .existing(one.id)
            && TradeRepublicDepotTarget.choose(accounts: [], linkedPortfolioID: nil) == .create
            && TradeRepublicDepotTarget.choose(accounts: [one, other], linkedPortfolioID: nil) == .ambiguous
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let aldi = #"{"items":[{"id":"aldi","timestamp":"2024-05-27T13:51:55.167+0000","title":"Aldi","eventType":"card_successful_transaction","status":"EXECUTED","amount":{"currency":"EUR","fractionDigits":2,"value":-5.95}}],"cursors":{"after":"next"}}"#
        let parsed = TradeRepublicTimeline.read(Data(aldi.utf8))
        let buy = TradeRepublicActivity(
            id: "buy1",
            date: day,
            title: "World",
            eventType: "ORDER_EXECUTED",
            amountCents: -4000,
            isin: "IE00B4L5Y983",
            trade: true,
            status: "EXECUTED",
            quantity: 2
        )
        let secondBuy = TradeRepublicActivity(
            id: "buy2",
            date: day.addingTimeInterval(3_600),
            title: "World",
            eventType: "ORDER_EXECUTED",
            amountCents: -4200,
            isin: "IE00B4L5Y983",
            trade: true,
            status: "EXECUTED",
            quantity: 2
        )
        let savingsBuy = TradeRepublicActivity(
            id: "save1",
            date: day,
            title: "World",
            eventType: "TRADING_SAVINGSPLAN_EXECUTED",
            amountCents: -2500,
            isin: "IE00B4L5Y983",
            trade: true,
            status: "EXECUTED",
            quantity: 1,
            savingsPlan: true
        )
        let held = HeldPosition(symbol: "IE00B4L5Y983", name: "World", quantity: 4, purchasePriceCents: 1000, latestLotDate: day.addingTimeInterval(-86400))
        let positionNow = TradeRepublicPosition(isin: "IE00B4L5Y983", name: "World", quantity: 8, averageBuyInCents: 1000)
        let grown = TradeRepublicSync.changes(positions: [positionNow], holdings: [held], activities: [buy, secondBuy, savingsBuy], known: [])
        let unsized = TradeRepublicSync.changes(positions: [positionNow], holdings: [held], activities: [
            TradeRepublicActivity(
                id: "plain",
                date: day,
                title: "World",
                eventType: "ORDER_EXECUTED",
                amountCents: -4000,
                isin: "IE00B4L5Y983",
                trade: true,
                status: "EXECUTED"
            )
        ], known: [])
        let detail = #"{"sections":[{"title":"Transaktion","data":[{"title":"Anteile","detail":{"text":"2 Stk."}},{"title":"Art","detail":{"text":"Sparplan"}}]}]}"#
        let enriched = TradeRepublicTimeline.enrich(
            TradeRepublicActivity(
                id: "plain",
                date: day,
                title: "World",
                eventType: "ORDER_EXECUTED",
                amountCents: -4000,
                isin: "IE00B4L5Y983",
                trade: true,
                status: "EXECUTED"
            ),
            detail: detail
        )
        let again = TradeRepublicSync.changes(positions: [positionNow], holdings: [held], activities: [buy], known: [TradeRepublicTimeline.fingerprint("buy1")])
        let soldDay = day.addingTimeInterval(86_400)
        let soldActivity = TradeRepublicActivity(
            id: "sale1",
            date: soldDay,
            title: "Apple",
            eventType: "ORDER_EXECUTED",
            amountCents: 1800,
            isin: "US0378331005",
            trade: true,
            status: "EXECUTED"
        )
        let sold = TradeRepublicSync.changes(
            positions: [],
            holdings: [HeldPosition(symbol: "US0378331005", name: "Apple", quantity: 2, purchasePriceCents: 500, latestLotDate: nil)],
            activities: [soldActivity],
            known: []
        )
        let soldWithoutEvent = TradeRepublicSync.changes(
            positions: [],
            holdings: [HeldPosition(symbol: "US0378331005", name: "Apple", quantity: 2, purchasePriceCents: 500, latestLotDate: nil)],
            activities: [],
            known: [],
            now: day
        )
        let buyQuantities: [Double] = grown.compactMap { move in
            if case .buy(_, _, _, _, _, let quantity, _, let savings) = move, !savings { return quantity }
            return nil
        }
        let savingsMarked = grown.contains { move in
            if case .buy(_, _, _, _, _, let quantity, _, let savings) = move { return savings && quantity == 1 }
            return false
        }
        let reading = "\(position?.quantity ?? 0), \(position?.averageBuyInCents ?? 0), \(kept.first?.purchasePriceCents == 1000 ? "behalten" : "neu")"
        let synced = parsed.items.first?.amountCents == -595
            && parsed.items.first?.title == "Aldi"
            && parsed.after == "next"
            && buyQuantities == [2, 2]
            && savingsMarked
            && !unsized.contains { if case .buy = $0 { return true }; return false }
            && enriched.quantity == 2
            && enriched.savingsPlan
            && abs((TradeRepublicTimeline.enrich(
                TradeRepublicActivity(
                    id: "fraction",
                    date: day,
                    title: "AI",
                    eventType: "TRADING_SAVINGSPLAN_EXECUTED",
                    amountCents: -500,
                    isin: "IE00BGV5VN51",
                    trade: true,
                    status: "EXECUTED",
                    savingsPlan: true
                ),
                detail: #"{"sections":[{"title":"Übersicht","data":[{"title":"Transaktion","detail":{"text":"0,025303 ×  197,60 €","displayValue":{"prefix":"0,025303 × ","text":"197,60 €"}}},{"title":"Aktienkurs","detail":{"text":"197,60 €"}}]}]}"#
            ).quantity ?? 0) - 0.025303) < 0.000001
            && !TradeRepublicTimeline.enrich(
                TradeRepublicActivity(
                    id: "plain",
                    date: day,
                    title: "NVIDIA",
                    eventType: "ORDER_EXECUTED",
                    amountCents: -30340,
                    isin: "US67066G1040",
                    trade: true,
                    status: "EXECUTED"
                ),
                detail: #"{"sections":[{"title":"Sparplan","data":[{"title":"Hinweis","detail":{"text":"Sparplan anlegen"}}]}]}"#
            ).savingsPlan
            && !again.contains { if case .buy(let id, _, _, _, _, _, _, _) = $0 { return id == "buy1" }; return false }
            && sold.contains { if case .sale(_, let date, _, let isin, _, let quantity, let amount) = $0 { return isin == "US0378331005" && quantity == 2 && amount == 1800 && date == soldDay }; return false }
            && sold.contains { if case .drop(let isin) = $0 { return isin == "US0378331005" }; return false }
            && !soldWithoutEvent.contains { if case .sale = $0 { return true }; return false }
            && !soldWithoutEvent.contains { if case .drop = $0 { return true }; return false }
        let incomeRows = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"div","timestamp":"2026-06-08T12:00:00.000Z","title":"Micron","subtitle":"Dividende","icon":"logos/US5951121038/v2","status":"EXECUTED","amount":{"value":31,"fractionDigits":2},"eventType":"DIVIDEND"},{"id":"zins","timestamp":"2026-06-01T12:00:00.000Z","title":"Zinsen","status":"EXECUTED","amount":{"value":13.28,"fractionDigits":2},"eventType":"INTEREST_PAYOUT"},{"id":"ipo","timestamp":"2026-06-05T12:00:00.000Z","title":"Anthropic","icon":"logos/US0000000000/v2","status":"EXECUTED","amount":{"value":-351,"fractionDigits":2},"eventType":"IPO_SUBSCRIPTION_CREATED"}]}"#.utf8))
        let income = TradeRepublicSync.changes(positions: [], holdings: [], activities: incomeRows.items, known: [])
        let dividendCash = income.contains { move in
            if case .cash(let id, _, _, let amount, let type) = move { return id == "div" && amount == 3100 && type == "Ertrag" }
            return false
        }
        let interestCash = income.contains { move in
            if case .cash(let id, _, _, let amount, let type) = move { return id == "zins" && amount == 1328 && type == "Zinsen" }
            return false
        }
        let ipoBooked = incomeRows.items.contains {
            $0.id == "ipo" && $0.statementType == "IPO" && $0.amountCents == -35_100
        } && income.contains { move in
            if case .cash(let id, _, _, let amount, let type) = move {
                return id == "ipo" && amount == -35_100 && type == "IPO"
            }
            return false
        }
        let fakeBuy = TradeRepublicActivity(
            id: "fake",
            date: day,
            title: "Micron",
            eventType: "DIVIDEND",
            amountCents: -3100,
            isin: "US5951121038",
            trade: true,
            status: "EXECUTED",
            quantity: 100
        )
        let realBuy = TradeRepublicActivity(
            id: "real",
            date: day,
            title: "Micron",
            eventType: "TRADING_TRADE_EXECUTED",
            amountCents: -40013,
            isin: "US5951121038",
            trade: true,
            status: "EXECUTED",
            quantity: 0.648464
        )
        let categories = parsed.items.first?.statementType == "Kartentransaktion"
            && incomeRows.items.first?.trade == false
            && dividendCash
            && interestCash
            && ipoBooked
            && !income.contains { if case .buy = $0 { return true }; return false }
            && !TradeRepublicSync.purchase(fakeBuy, averageCents: 79522)
            && TradeRepublicSync.purchase(realBuy, averageCents: 79522)
        let saveback = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"back","timestamp":"2026-11-02T12:00:00.000Z","title":"MSCI World","icon":"logos/IE00BJ0KDQ92/v2","status":"EXECUTED","amount":{"value":-15,"fractionDigits":2},"eventType":"SAVEBACK_AGGREGATE"}]}"#.utf8))
        let namedSaveback = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"back2","timestamp":"2026-11-02T12:00:00.000Z","title":"MSCI World","icon":"logos/IE00BJ0KDQ92/v2","status":"EXECUTED","amount":{"value":-15,"fractionDigits":2},"eventType":"benefits_saveback_execution"}]}"#.utf8))
        let perk = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"perk","timestamp":"2024-01-03T12:00:00.000Z","title":"Apple","icon":"logos/US0378331005/v2","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"ACQUISITION_TRADE_PERK"}]}"#.utf8))
        let gift = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"gift","timestamp":"2024-01-03T12:00:00.000Z","title":"Apple","subtitle":"Geschenk","icon":"logos/US0378331005/v2","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"}]}"#.utf8))
        let unexplained = TradeRepublicSync.changes(
            positions: [TradeRepublicPosition(isin: "US0378331005", name: "Apple", quantity: 1, averageBuyInCents: 1010)],
            holdings: [],
            activities: [],
            known: []
        )
        let nvidia = TradeRepublicActivity(
            id: "nvda",
            date: day,
            title: "NVIDIA",
            eventType: "TRADING_TRADE_EXECUTED",
            amountCents: -30340,
            isin: "US67066G1040",
            trade: true,
            status: "EXECUTED",
            quantity: 2
        )
        let tobacco = TradeRepublicPosition(isin: "GB0002875804", name: "Tobacco", quantity: 0.436442, averageBuyInCents: 5724)
        let poisoned = TradeRepublicSync.changes(positions: [tobacco], holdings: [], activities: [nvidia], known: [])
        let giftDay = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"bat-gift","timestamp":"2026-11-06T12:00:00.000Z","title":"Tobacco","icon":"logos/GB0002875804/v2","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"}]}"#.utf8)).items.first?.date
        let gifted = TradeRepublicSync.changes(
            positions: [tobacco],
            holdings: [],
            activities: [nvidia] + TradeRepublicTimeline.read(Data(#"{"items":[{"id":"bat-gift","timestamp":"2026-11-06T12:00:00.000Z","title":"Tobacco","icon":"logos/GB0002875804/v2","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"}]}"#.utf8)).items,
            known: []
        )
        let unnamedGift = TradeRepublicTimeline.read(Data(#"{"items":[{"id":"gift-anon","timestamp":"2026-11-06T12:00:00.000Z","title":"Geschenk","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"}]}"#.utf8)).items
        let giftedUnnamed = TradeRepublicSync.changes(
            positions: [tobacco],
            holdings: [],
            activities: [nvidia] + unnamedGift,
            known: []
        )
        let world = TradeRepublicPosition(isin: "IE00B4L5Y983", name: "World", quantity: 2, averageBuyInCents: 8000)
        let worldBuys = [
            TradeRepublicActivity(
                id: "w1",
                date: day,
                title: "World",
                eventType: "TRADING_TRADE_EXECUTED",
                amountCents: -8000,
                isin: "IE00B4L5Y983",
                trade: true,
                status: "EXECUTED",
                quantity: 1.5
            ),
            TradeRepublicActivity(
                id: "w2",
                date: day,
                title: "World",
                eventType: "TRADING_TRADE_EXECUTED",
                amountCents: -8000,
                isin: "IE00B4L5Y983",
                trade: true,
                status: "EXECUTED",
                quantity: 1.5
            )
        ]
        let worldMoves = TradeRepublicSync.changes(positions: [world], holdings: [], activities: worldBuys, known: [])
        let coin = TradeRepublicPosition(isin: "XF000BTC0017", name: "Bitcoin", quantity: 0.006526, averageBuyInCents: 5_871_231)
        let coinBuy = TradeRepublicActivity(
            id: "btc-buy",
            date: day,
            title: "Bitcoin",
            eventType: "TRADING_TRADE_EXECUTED",
            amountCents: -59979,
            isin: "XF000BTC0017",
            trade: true,
            status: "EXECUTED",
            quantity: 0.010439
        )
        let coinSale = TradeRepublicActivity(
            id: "btc-sale",
            date: day.addingTimeInterval(86_400),
            title: "Bitcoin",
            eventType: "TRADING_TRADE_EXECUTED",
            amountCents: 28000,
            isin: "XF000BTC0017",
            trade: true,
            status: "EXECUTED",
            quantity: 0.003913
        )
        let coins = TradeRepublicSync.changes(positions: [coin], holdings: [], activities: [coinBuy, coinSale], known: [])
        let closedBuy = TradeRepublicActivity(
            id: "buy-apple",
            date: day,
            title: "Apple",
            eventType: "ORDER_EXECUTED",
            amountCents: -1000,
            isin: "US0378331005",
            trade: true,
            status: "EXECUTED",
            quantity: 2
        )
        let closed = TradeRepublicSync.changes(
            positions: [],
            holdings: [],
            activities: [closedBuy, soldActivity],
            known: []
        )
        let privateShare = TradeRepublicPosition(isin: "US84615Q1031", name: "SpaceX", quantity: 0.497296, averageBuyInCents: 12079)
        let privateBuys = [
            TradeRepublicActivity(
                id: "sx1",
                date: day,
                title: "SpaceX",
                eventType: "TRADING_TRADE_EXECUTED",
                amountCents: -15371,
                isin: "US84615Q1031",
                trade: true,
                status: "EXECUTED",
                quantity: 1
            ),
            TradeRepublicActivity(
                id: "sx2",
                date: day.addingTimeInterval(60),
                title: "SpaceX",
                eventType: "TRADING_TRADE_EXECUTED",
                amountCents: -13101,
                isin: "US84615Q1031",
                trade: true,
                status: "EXECUTED",
                quantity: 1
            )
        ]
        let scaled = TradeRepublicSync.changes(positions: [privateShare], holdings: [], activities: privateBuys, known: [])
        let scaledQuantities = scaled.compactMap { move -> Double? in
            if case .buy(_, _, _, _, _, let quantity, _, _) = move { return quantity }
            return nil
        }
        let indexJSON = #"{"items":[{"id":"keep","timestamp":"2026-11-06T12:00:00.000Z","title":"Tobacco","icon":"logos/GB0002875804/v2","status":"EXECUTED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"},{"id":"skip","timestamp":"2026-11-06T12:00:00.000Z","title":"Pending","status":"CANCELED","amount":{"value":0,"fractionDigits":2},"eventType":"INCOMING_GIFT"}]}"#
        let indexLines = TradeRepublicTimeline.indexLines(from: indexJSON)
        let fromIndex = TradeRepublicTimeline.activities(fromIndex: indexLines.joined(separator: "\n"))
        let sample = TradeRepublicSample.snapshot(from: "===== timelineIndex =====\n" + indexLines.joined(separator: "\n"))
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let fourteenth = berlin.date(from: DateComponents(year: 2026, month: 11, day: 14)) ?? day
        let sixteenth = berlin.date(from: DateComponents(year: 2026, month: 11, day: 16)) ?? day
        let receipts = saveback.items.first?.trade == false
            && saveback.items.first?.statementType == "Cashback"
            && namedSaveback.items.first?.trade == false
            && namedSaveback.items.first?.statementType == "Cashback"
            && perk.items.first?.trade == false
            && perk.items.first?.statementType == "Depotgeschenk"
            && gift.items.first?.statementType == "Depotgeschenk"
            && gift.items.first?.trade == false
            && !unexplained.contains { if case .buy = $0 { return true }; return false }
            && unexplained.contains { move in
                if case .grant(_, _, _, let isin, _, let quantity, _, let type) = move {
                    return isin == "US0378331005" && abs(quantity - 1) < 0.000001 && type == "Depotgeschenk"
                }
                return false
            }
            && poisoned.contains { move in
                if case .grant(_, _, _, let isin, _, _, _, let type) = move {
                    return isin == "GB0002875804" && type == "Depotgeschenk"
                }
                return false
            }
            && !poisoned.contains { if case .shares = $0 { return true }; return false }
            && gifted.contains { move in
                if case .grant(_, let date, _, let isin, _, let quantity, let amount, let type) = move {
                    return isin == "GB0002875804"
                        && date == giftDay
                        && amount == 0
                        && type == "Depotgeschenk"
                        && abs(quantity - 0.436442) < 0.000001
                }
                return false
            }
            && giftedUnnamed.contains { move in
                if case .grant(_, let date, _, let isin, _, _, _, _) = move {
                    return isin == "GB0002875804" && date == unnamedGift.first?.date
                }
                return false
            }
            && !worldMoves.contains { if case .sale = $0 { return true }; return false }
            && abs(worldMoves.compactMap { move -> Double? in
                if case .buy(_, _, _, _, _, let quantity, _, _) = move { return quantity }
                return nil
            }.reduce(0, +) - 2) < 0.00001
            && !TradeRepublicSample.clipsExtract
            && coins.contains { move in
                if case .sale(_, _, _, let isin, _, let quantity, _) = move {
                    return isin == "XF000BTC0017" && abs(quantity - 0.003913) < 0.000001
                }
                return false
            }
            && closed.contains { if case .buy(let id, _, _, _, _, _, _, _) = $0 { return id == "buy-apple" }; return false }
            && closed.contains { if case .sale(let id, _, _, _, _, _, _) = $0 { return id == "sale1" }; return false }
            && closed.contains { if case .drop(let isin) = $0 { return isin == "US0378331005" }; return false }
            && scaledQuantities.count == 2
            && scaledQuantities.allSatisfy { abs($0 - 0.248648) < 0.00001 }
            && !scaled.contains { if case .sale = $0 { return true }; return false }
            && MarketDataService.cryptoTicker(from: "XF000BTC0017") == "BTC"
            && MarketDataService.isQuoteable("XF000BTC0017")
            && !MarketDataService.isValidISIN("XF000BTC0017")
            && indexLines.count == 2
            && fromIndex.contains(where: { $0.id == "keep" && $0.statementType == "Depotgeschenk" })
            && !fromIndex.contains(where: { $0.id == "skip" })
            && sample?.activities.contains(where: { $0.id == "keep" }) == true
            && BankImportApplier.ownAccountWindowDays == 3
            && BankNotice.transferWindowDays == BankImportApplier.ownAccountWindowDays
            && abs(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: fourteenth), to: Calendar.current.startOfDay(for: sixteenth)).day ?? 99) == 2
            && sessionImportReplacesPreviousTradeRepublic()
        return result("Ein Depotstand setzt Menge und Einstand und erfindet nichts", .portfolio, .unit, passed && synced && categories && receipts, reading)
    }

    private static func deadSessionDoesNotStartAnotherLogin() -> LififyCheckResult {
        let dead = TradeRepublicRequest.failure(statusCode: 401, errorCode: nil, savedSession: true)
        let notStarted = TradeRepublicRequest.failure(statusCode: 401, errorCode: nil)
        let duringProcess = TradeRepublicRequest.failure(statusCode: 401, errorCode: nil, duringProcess: true)
        let wrongPin = TradeRepublicRequest.failure(statusCode: 401, errorCode: "PIN_INVALID")
        let invalidNumber = TradeRepublicRequest.failure(statusCode: 400, errorCode: TradeRepublicGap.probedCode)
        let header = "tr_session=example"
        let message = TradeRepublicFailure.sessionDead.message
        let headers = TradeRepublicRequest.headers()
        let again = TradeRepublicRequest.headers()
        let passed = dead == .sessionDead
            && notStarted == .notStarted
            && duringProcess == .sessionNotKept
            && !TradeRepublicCookies.keepsSession("JSESSIONID=abc")
            && wrongPin == .invalidPin
            && invalidNumber == .invalidPhone
            && TradeRepublicRequest.canonicalPhone("0176 123") == "+49176123"
            && TradeRepublicRequest.canonicalPhone("+49 170") == "+49170"
            && headers["X-TR-Device-Info"] == again["X-TR-Device-Info"]
            && TradeRepublicRefresh.manualOnly
            && !TradeRepublicRefresh.onLaunch
            && !TradeRepublicRefresh.onTimer
            && !TradeRepublicRefresh.onFinanceOpen
            && !TradeRepublicRefresh.usesStoredPIN
            && TradeRepublicGap.deviceConfirmationRequired
            && !TradeRepublicGap.completedOnThisMachine
            && TradeRepublicCookies.keepsSession(header)
            && !TradeRepublicCookies.keepsSession("aws-waf-token=example")
            && !message.localizedCaseInsensitiveContains("example")
            && !message.localizedCaseInsensitiveContains("tr_session")
            && headers["X-Tr-Platform"] == TradeRepublicRequest.platform
            && headers["X-TR-App-Version"] == TradeRepublicRequest.appVersion
            && headers["X-TR-Device-Info"]?.isEmpty == false
        let reading = "401 manual"
        return result("Eine tote Sitzung startet keine neue Anmeldung", .account, .unit, passed, reading)
    }

    private static func sparkasseAndTradeRepublicLandOnTheMatchingAccount() -> LififyCheckResult {
        let sparkasse = UUID()
        let main = UUID()
        let trade = UUID()
        let portfolio = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let accounts = [
            NamedAccount(id: sparkasse, name: "Sparkasse", kind: .checking, isMain: false),
            NamedAccount(id: main, name: "Giro", kind: .checking, isMain: true),
            NamedAccount(id: trade, name: "Trade Republic", kind: .checking, isMain: false),
            NamedAccount(id: portfolio, name: "Depot", kind: .portfolio, isMain: false)
        ]
        let first = BankNotice.plan(
            text: "Kartenzahlung 4,20 EUR REWE",
            bank: .sparkasse,
            accounts: accounts,
            existing: [],
            now: now
        )
        let entry = LedgerEntry(
            date: now,
            title: "REWE",
            amountCents: -420,
            kind: .expense,
            accountID: sparkasse
        )
        let mapped = BankNotice.booked(entry)
        let second = BankNotice.plan(
            text: "Abbuchung 4,20 EUR REWE SAGT DANKE",
            bank: .sparkasse,
            accounts: accounts,
            existing: mapped.map { [$0] } ?? [],
            now: now.addingTimeInterval(60)
        )
        let deposit = BankNotice.plan(
            text: "Einzahlung 50,00 EUR",
            bank: .tradeRepublic,
            accounts: accounts,
            existing: [],
            now: now
        )
        let spent = BankNotice.plan(
            text: "10,00 € bei Tabakwaren Dietz ausgegeben",
            bank: .tradeRepublic,
            accounts: accounts,
            existing: [],
            now: now
        )
        let wire = BankNotice.plan(
            text: "Überweisung erhalten\nDu hast 2.000,00 € von Someone erhalten",
            bank: .tradeRepublic,
            accounts: accounts,
            existing: [],
            now: now
        )
        let transfer = LedgerEntry(
            date: now.addingTimeInterval(-2 * 24 * 60 * 60),
            title: "Umbuchung",
            amountCents: 200_000,
            kind: .transfer,
            fromAccountID: main,
            toAccountID: trade
        )
        let wireAgain = BankNotice.plan(
            text: "Überweisung erhalten\nDu hast 2.000,00 € von Someone erhalten",
            bank: .tradeRepublic,
            accounts: accounts,
            existing: BankNotice.records(transfer),
            now: now
        )
        let url = URL(string: "lifify://notice?account=sparkasse&text=Abbuchung%2012%2C34%20EUR%20REWE")
        let decoded = url.flatMap(BankNoticeURL.decode)
        let sparkasseBooked = bookedAmount(first) == -420 && bookedAccount(first) == sparkasse
        let tradeBooked = bookedAmount(deposit) == 5000 && bookedAccount(deposit) == trade
        let passed = sparkasseBooked
            && second == .duplicate
            && tradeBooked
            && bookedAccount(deposit) != portfolio
            && bookedAmount(spent) == -1000
            && bookedAccount(spent) == trade
            && bookedAmount(wire) == 200_000
            && bookedAccount(wire) == trade
            && isTransferPlan(wire)
            && wireAgain == .duplicate
            && mapped?.direction == .out
            && decoded?.bank == .sparkasse
            && decoded?.text == "Abbuchung 12,34 EUR REWE"
        let reading = "Sparkasse -420, duplicate, Trade Republic 5000"
        return result("Sparkasse und Trade Republic landen auf dem passenden Konto", .bankImport, .integration, passed, reading)
    }

    private static func signInAndRefreshStayManual() -> LififyCheckResult {
        let signIn = OnboardingSteps.tradeRepublicSignIn
        let passed = OnboardingSteps.count == 9
            && OnboardingSteps.tradeRepublic == "Trade Republic"
            && (signIn == "Trade Republic anmelden (optional)" || signIn == "Sign in to Trade Republic (optional)")
            && (TradeRepublicCopy.signIn == "Bei Trade Republic anmelden" || TradeRepublicCopy.signIn == "Sign in to Trade Republic")
            && !TradeRepublicRefresh.storesSession
            && TradeRepublicRefresh.manualOnly
            && !TradeRepublicRefresh.onLaunch
            && !TradeRepublicRefresh.onTimer
            && !TradeRepublicRefresh.onFinanceOpen
            && !TradeRepublicRefresh.usesStoredPIN
            && TradeRepublicGap.probedStatus == 400
            && TradeRepublicGap.probedCode == "NUMBER_INVALID"
            && KeychainStore.deviceOnly == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
            && KeychainStore.tradeRepublicService == "lifify.traderepublic"
            && AppChrome.version == "0.5.0"
        let reading = "9 manual 400"
        return result("Anmeldung und Aktualisieren laufen nur von Hand", .account, .integration, passed, reading)
    }

    private static func bookedAmount(_ plan: BankNoticePlan) -> Int? {
        switch plan {
        case .book(_, _, let amount, _), .bookTransfer(_, _, _, let amount):
            return amount
        case .duplicate, .unreadable, .missingAccount:
            return nil
        }
    }

    private static func bookedAccount(_ plan: BankNoticePlan) -> UUID? {
        switch plan {
        case .book(let accountID, _, _, _):
            return accountID
        case .bookTransfer(_, let toAccountID, _, _):
            return toAccountID
        case .duplicate, .unreadable, .missingAccount:
            return nil
        }
    }

    private static func isTransferPlan(_ plan: BankNoticePlan) -> Bool {
        if case .bookTransfer = plan { return true }
        return false
    }

    private static func sessionImportReplacesPreviousTradeRepublic() -> Bool {
        let checking = UUID()
        let portfolio = UUID()
        let other = UUID()
        let session = LedgerEntry(
            title: "Kauf",
            amountCents: 100,
            kind: .transfer,
            fromAccountID: checking,
            toAccountID: portfolio,
            importFingerprint: "tr-buy"
        )
        let start = LedgerEntry(
            title: "Startsaldo",
            amountCents: 1,
            kind: .adjustment,
            accountID: checking,
            importFingerprint: TradeRepublicTimeline.openingBalanceFingerprint
        )
        let own = LedgerEntry(
            title: "Umbuchung",
            amountCents: 200_000,
            kind: .transfer,
            fromAccountID: other,
            toAccountID: checking,
            importFingerprint: "csv-1"
        )
        let card = LedgerEntry(
            title: "Tabakwaren Dietz",
            amountCents: -1000,
            kind: .expense,
            accountID: checking
        )
        return TradeRepublicDepotApplier.shouldReplace(session, checkingID: checking, portfolioID: portfolio)
            && !TradeRepublicDepotApplier.shouldReplace(start, checkingID: checking, portfolioID: portfolio)
            && !TradeRepublicDepotApplier.shouldReplace(own, checkingID: checking, portfolioID: portfolio)
            && !TradeRepublicDepotApplier.shouldReplace(card, checkingID: checking, portfolioID: portfolio)
    }

    private static func result(
        _ name: String,
        _ topic: LififyCheckTopic,
        _ kind: LififyCheckKind,
        _ passed: Bool,
        _ reading: String
    ) -> LififyCheckResult {
        LififyCheckResult(
            name: name,
            passed: passed,
            detail: passed ? nil : reading,
            reading: reading,
            kind: kind,
            topic: topic
        )
    }
}
