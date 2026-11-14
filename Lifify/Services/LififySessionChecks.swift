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
        let reading = "\(position?.quantity ?? 0), \(position?.averageBuyInCents ?? 0), \(kept.first?.purchasePriceCents == 1000 ? "behalten" : "neu")"
        return result("Ein Depotstand setzt Menge und Einstand und erfindet nichts", .portfolio, .unit, passed, reading)
    }

    private static func deadSessionDoesNotStartAnotherLogin() -> LififyCheckResult {
        let dead = TradeRepublicRequest.failure(statusCode: 401, errorCode: nil)
        let invalidNumber = TradeRepublicRequest.failure(statusCode: 400, errorCode: TradeRepublicGap.probedCode)
        let header = "tr_session=example"
        let message = TradeRepublicFailure.sessionDead.message
        let headers = TradeRepublicRequest.headers()
        let passed = dead == .sessionDead
            && invalidNumber == .invalidPhone
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
        let url = URL(string: "lifify://notice?account=sparkasse&text=Abbuchung%2012%2C34%20EUR%20REWE")
        let decoded = url.flatMap(BankNoticeURL.decode)
        let sparkasseBooked = bookedAmount(first) == -420 && bookedAccount(first) == sparkasse
        let tradeBooked = bookedAmount(deposit) == 5000 && bookedAccount(deposit) == trade
        let passed = sparkasseBooked
            && second == .duplicate
            && tradeBooked
            && bookedAccount(deposit) != portfolio
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
            && (TradeRepublicCopy.refresh == "Depot aus der Sitzung aktualisieren" || TradeRepublicCopy.refresh == "Refresh the depot from the session")
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
        if case .book(_, _, let amount, _) = plan { return amount }
        return nil
    }

    private static func bookedAccount(_ plan: BankNoticePlan) -> UUID? {
        if case .book(let accountID, _, _, _) = plan { return accountID }
        return nil
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
