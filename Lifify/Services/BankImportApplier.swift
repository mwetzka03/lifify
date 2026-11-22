import Foundation
import SwiftData

struct BankImportResult {
    var importedCount: Int
    var holdingCount: Int
    var accountName: String
    var checkingAccountID: UUID
    var createdSeparateChecking: Bool
    var entryIDs: [String: UUID]
    var selectableRows: [ImportedTransaction]
    var skippedBeforeStart: Int = 0
    var review: ImportReview = ImportReview()
}

@MainActor
enum ImportBalance {
    static let currentFingerprint = "saldo-korrektur"

    static func openingCents(current: Int, rowAmounts: [Int]) -> Int {
        current - rowAmounts.reduce(0, +)
    }

    static func correctionCents(current: Int, computed: Int) -> Int {
        current - computed
    }

    static func fittedOpeningCents(current: Int, laterEffect: Int) -> Int {
        current - laterEffect
    }

    static func isCurrentPin(_ entry: LedgerEntry, accountID: UUID) -> Bool {
        guard entry.accountID == accountID, entry.kind == .adjustment else { return false }
        if entry.importFingerprint == currentFingerprint { return true }
        return entry.notes.contains("Typ: Saldo-Korrektur")
    }

    /// First import: the opening on day one is current minus every later booking.
    /// Later import: skip old rows, then a Saldo-Korrektur from the last import.
    @discardableResult
    static func fitToCurrent(
        account: Account,
        entries: inout [LedgerEntry],
        currentCents: Int,
        context: ModelContext
    ) -> LedgerEntry? {
        removeAbsolutePins(accountID: account.id, entries: &entries, context: context)
        let result: LedgerEntry?
        if BankImportCursor.currentCents(for: account.id) == nil {
            result = fitFirstOpening(account: account, entries: &entries, currentCents: currentCents, context: context)
        } else {
            result = insertDelta(account: account, entries: &entries, currentCents: currentCents, context: context)
        }
        return result
    }

    /// Rewrites the first opening so FinanceService live cash equals the entered stand.
    @discardableResult
    static func fitFirstOpening(
        account: Account,
        entries: inout [LedgerEntry],
        currentCents: Int,
        context: ModelContext
    ) -> LedgerEntry? {
        let opening = firstOpening(accountID: account.id, in: entries) ?? makeOpening(
            account: account,
            entries: &entries,
            context: context
        )
        anchorOpening(opening, entries: &entries, context: context)
        let computed = FinanceService.currentBalance(for: account, entries: entries)
        opening.amountCents += currentCents - computed
        return opening
    }

    /// Turns a leftover today's pin into a fitted first-day opening.
    static func adoptPinsIfNeeded(
        accounts: [Account],
        entries: inout [LedgerEntry],
        context: ModelContext
    ) -> [(accountID: UUID, currentCents: Int)] {
        var changed: [(accountID: UUID, currentCents: Int)] = []
        for account in accounts where account.kind != .portfolio && account.kind != .savingsGroup {
            guard !isTradeRepublicChecking(account, entries: entries) else { continue }
            guard let pin = entries.filter({ isCurrentPin($0, accountID: account.id) }).max(by: { $0.createdAt < $1.createdAt }) else {
                continue
            }
            let current = pin.amountCents
            removeAbsolutePins(accountID: account.id, entries: &entries, context: context)
            _ = fitFirstOpening(account: account, entries: &entries, currentCents: current, context: context)
            changed.append((account.id, current))
        }
        return changed
    }

    /// Same-day bookings must sit after the opening, or Endsaldo and live cash diverge.
    static func repairOpeningAnchors(
        accounts: [Account],
        entries: inout [LedgerEntry],
        context: ModelContext
    ) -> Bool {
        var changed = false
        for account in accounts where account.kind != .portfolio && account.kind != .savingsGroup {
            guard !isTradeRepublicChecking(account, entries: entries) else { continue }
            guard let opening = firstOpening(accountID: account.id, in: entries) else { continue }
            if anchorOpening(opening, entries: &entries, context: context) {
                changed = true
            }
        }
        return changed
    }

    /// Absolute pin for callers that still need today's stand as the last adjustment.
    @discardableResult
    static func correction(
        account: Account,
        entries: inout [LedgerEntry],
        currentCents: Int,
        date: Date,
        context: ModelContext
    ) -> LedgerEntry? {
        let day = Calendar.current.startOfDay(for: date)
        let stale = entries.filter { isCurrentPin($0, accountID: account.id) }
        if let existing = stale.max(by: { $0.createdAt < $1.createdAt }) {
            for entry in stale where entry.id != existing.id {
                context.delete(entry)
            }
            entries.removeAll { isCurrentPin($0, accountID: account.id) && $0.id != existing.id }
            existing.date = day
            existing.amountCents = currentCents
            existing.kind = .adjustment
            existing.title = L("Saldo-Korrektur", "Balance adjustment")
            existing.notes = "Typ: Saldo-Korrektur"
            existing.importFingerprint = currentFingerprint
            existing.accountID = account.id
            return existing
        }
        let entry = LedgerEntry(
            date: day,
            title: L("Saldo-Korrektur", "Balance adjustment"),
            notes: "Typ: Saldo-Korrektur",
            amountCents: currentCents,
            kind: .adjustment,
            accountID: account.id,
            importFingerprint: currentFingerprint
        )
        context.insert(entry)
        entries.append(entry)
        return entry
    }

    private static func removeAbsolutePins(
        accountID: UUID,
        entries: inout [LedgerEntry],
        context: ModelContext
    ) {
        let stale = entries.filter { isCurrentPin($0, accountID: accountID) }
        for entry in stale {
            context.delete(entry)
        }
        entries.removeAll { isCurrentPin($0, accountID: accountID) }
    }

    private static func firstOpening(accountID: UUID, in entries: [LedgerEntry]) -> LedgerEntry? {
        entries
            .filter { $0.kind == .adjustment && $0.accountID == accountID && !isCurrentPin($0, accountID: accountID) }
            .sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.createdAt < rhs.createdAt : lhs.date < rhs.date
            }
            .first
    }

    private static func makeOpening(
        account: Account,
        entries: inout [LedgerEntry],
        context: ModelContext
    ) -> LedgerEntry {
        let first = entries
            .filter { $0.accountID == account.id || $0.fromAccountID == account.id || $0.toAccountID == account.id }
            .map(\.date)
            .min() ?? Date()
        let day = Calendar.current.startOfDay(for: first)
        let opening = LedgerEntry(
            date: day,
            title: L("Eröffnungssaldo", "Opening balance"),
            amountCents: 0,
            kind: .adjustment,
            accountID: account.id,
            createdAt: day
        )
        context.insert(opening)
        entries.append(opening)
        return opening
    }

    private static func insertDelta(
        account: Account,
        entries: inout [LedgerEntry],
        currentCents: Int,
        context: ModelContext
    ) -> LedgerEntry? {
        let computed = FinanceService.currentBalance(for: account, entries: entries)
        let delta = correctionCents(current: currentCents, computed: computed)
        guard delta != 0 else { return nil }
        let last = BankImportCursor.date(for: account.id) ?? Date()
        let entry = LedgerEntry(
            date: Calendar.current.startOfDay(for: last),
            title: L("Saldo-Korrektur", "Balance adjustment"),
            notes: "Typ: Saldo-Korrektur",
            amountCents: delta,
            kind: delta >= 0 ? .income : .expense,
            accountID: account.id
        )
        context.insert(entry)
        entries.append(entry)
        return entry
    }

    @discardableResult
    private static func anchorOpening(
        _ opening: LedgerEntry,
        entries: inout [LedgerEntry],
        context: ModelContext
    ) -> Bool {
        let day = Calendar.current.startOfDay(for: opening.date)
        var changed = false
        if opening.date != day {
            opening.date = day
            changed = true
        }
        if opening.createdAt != day {
            opening.createdAt = day
            changed = true
        }
        let extras = entries.filter {
            $0.id != opening.id
                && $0.kind == .adjustment
                && $0.accountID == opening.accountID
                && isOpeningTitle($0)
        }
        for extra in extras {
            context.delete(extra)
            changed = true
        }
        if !extras.isEmpty {
            let ids = Set(extras.map(\.id))
            entries.removeAll { ids.contains($0.id) }
        }
        return changed
    }

    private static func isOpeningTitle(_ entry: LedgerEntry) -> Bool {
        entry.title == L("Eröffnungssaldo", "Opening balance")
            || entry.title == L("Startsaldo", "Opening balance")
            || entry.title == "Eröffnungssaldo"
            || entry.title == "Startsaldo"
            || entry.title == "Opening balance"
    }

    private static func isTradeRepublicChecking(_ account: Account, entries: [LedgerEntry]) -> Bool {
        entries.contains {
            $0.accountID == account.id
                && ($0.importFingerprint == TradeRepublicTimeline.openingBalanceFingerprint
                    || $0.importFingerprint == "tr-startsaldo")
        }
    }
}

enum BankImportCursor {
    private static let prefix = "lifify.bankImport.cursor."
    private static let currentPrefix = "lifify.bankImport.current."

    static func date(for accountID: UUID) -> Date? {
        let stored = AppDefaults.store.double(forKey: key(accountID))
        guard stored > 0 else { return nil }
        return Date(timeIntervalSince1970: stored)
    }

    static func currentCents(for accountID: UUID) -> Int? {
        let key = currentKey(accountID)
        guard AppDefaults.store.object(forKey: key) != nil else { return nil }
        return AppDefaults.store.integer(forKey: key)
    }

    static func mark(_ accountID: UUID, at date: Date = Date(), currentCents: Int? = nil) {
        AppDefaults.store.set(date.timeIntervalSince1970, forKey: key(accountID))
        if let currentCents {
            AppDefaults.store.set(currentCents, forKey: currentKey(accountID))
        }
    }

    static func reset() {
        let defaults = AppDefaults.store
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(prefix) || key.hasPrefix(currentPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(_ accountID: UUID) -> String {
        prefix + accountID.uuidString
    }

    private static func currentKey(_ accountID: UUID) -> String {
        currentPrefix + accountID.uuidString
    }
}

@MainActor
enum PortfolioLinkStore {
    private static var cached: [UUID: UUID]?

    static func clearCache() {
        cached = nil
    }

    static func portfolioID(for checkingID: UUID) -> UUID? {
        snapshot()[checkingID]
    }

    static func link(portfolio portfolioID: UUID, to checkingID: UUID) {
        var map = snapshot().filter { $0.value != portfolioID }
        map[checkingID] = portfolioID
        save(map)
    }

    static func checkingID(for portfolioID: UUID) -> UUID? {
        snapshot().first { $0.value == portfolioID }?.key
    }

    static func unlink(checkingID: UUID) {
        var map = snapshot()
        map.removeValue(forKey: checkingID)
        save(map)
    }

    static func unlink(portfolio portfolioID: UUID) {
        save(snapshot().filter { $0.value != portfolioID })
    }

    static func allLinks() -> [(checkingID: UUID, portfolioID: UUID)] {
        snapshot().map { (checkingID: $0.key, portfolioID: $0.value) }
    }

    private static func snapshot() -> [UUID: UUID] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredPortfolioLink>())
        let map = Dictionary(rows.map { ($0.checkingID, $0.portfolioID) }, uniquingKeysWith: { first, _ in first })
        cached = map
        return map
    }

    private static func save(_ map: [UUID: UUID]) {
        guard map != snapshot() else { return }
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredPortfolioLink>())) ?? []).forEach(context.delete)
            LififyDatabase.saveSide()
            for (checkingID, portfolioID) in map {
                context.insert(StoredPortfolioLink(checkingID: checkingID, portfolioID: portfolioID))
            }
            LififyDatabase.saveSide()
        }
        cached = map
    }
}

@MainActor
enum PortfolioConsolidation {
    static func consolidate(context: ModelContext) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let portfolios = accounts.filter { $0.kind == .portfolio }
        guard !portfolios.isEmpty else { return }
        var changed = false
        for portfolio in portfolios where portfolio.isLiquid {
            portfolio.isLiquid = false
            changed = true
        }
        if portfolios.count == 1, let only = portfolios.first, isGeneratedName(only.name) {
            only.name = L("Depot", "Portfolio")
            changed = true
        }
        if changed { try? context.save() }
    }

    static func isGeneratedName(_ name: String) -> Bool {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        return folded.hasPrefix("depot ·") || folded.hasPrefix("portfolio ·")
    }
}

@MainActor
enum BankImportApplier {
    static func apply(
        document: BankImportDocument,
        to destination: BankImportDestination,
        currentBalanceCents: Int? = nil,
        detectDuplicates: Bool = true,
        context: ModelContext
    ) throws -> BankImportResult {
        if document.tradeRepublic != nil {
            PortfolioConsolidation.consolidate(context: context)
        }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        var entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        var holdings = try context.fetch(FetchDescriptor<PortfolioHolding>())
        let checking = try checkingAccount(for: document, destination: destination, accounts: accounts, context: context)
        let portfolio = portfolioAccount(for: checking.account, document: document, context: context)
        var insertedEntries: [LedgerEntry] = []
        var insertedHoldings: [PortfolioHolding] = []
        let insertedAccounts = checking.created + (portfolio?.created ?? [])
        if document.tradeRepublic != nil {
            replacePreviousStatement(
                on: checking.account.id,
                portfolioID: portfolio?.account.id,
                entries: &entries,
                holdings: &holdings,
                context: context
            )
        }
        let period = document.tradeRepublic == nil
            ? nil
            : firstMainAccountPeriod(entries: entries, accounts: accounts, context: context)

        if document.tradeRepublic == nil, let currentBalanceCents,
           !entries.contains(where: {
               $0.kind == .adjustment
                   && $0.accountID == checking.account.id
                   && !ImportBalance.isCurrentPin($0, accountID: checking.account.id)
           }),
           let firstDate = document.rows.map(\.date).min() {
            let opening = ImportBalance.openingCents(
                current: currentBalanceCents,
                rowAmounts: document.rows.map(\.amountCents)
            )
            let day = Calendar.current.startOfDay(for: firstDate)
            let adjustment = LedgerEntry(
                date: day,
                title: L("Eröffnungssaldo", "Opening balance"),
                amountCents: opening,
                kind: .adjustment,
                accountID: checking.account.id,
                createdAt: day
            )
            context.insert(adjustment)
            insertedEntries.append(adjustment)
            entries.append(adjustment)
        } else if let statement = document.tradeRepublic, let period {
            let saldo = statementBalance(
                before: period.start,
                rows: document.rows,
                opening: statement.openingBalanceCents
            )
            let adjustment = LedgerEntry(
                date: Calendar.current.startOfDay(for: period.start),
                title: L("Startsaldo", "Opening balance"),
                notes: "Typ: Startsaldo",
                amountCents: saldo,
                kind: .adjustment,
                accountID: checking.account.id,
                importFingerprint: "tr-startsaldo"
            )
            context.insert(adjustment)
            insertedEntries.append(adjustment)
            entries.append(adjustment)
        } else if let statement = document.tradeRepublic, statement.openingBalanceCents != 0,
                  !entries.contains(where: { entryTouches($0, accountID: checking.account.id) }),
                  let firstDate = document.rows.map(\.date).min() {
            let adjustment = LedgerEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: firstDate) ?? firstDate,
                title: L("Eröffnungssaldo", "Opening balance"),
                amountCents: statement.openingBalanceCents,
                kind: .adjustment,
                accountID: checking.account.id
            )
            context.insert(adjustment)
            insertedEntries.append(adjustment)
        }

        var known = Set(entries.compactMap(\.importFingerprint))
        var entryIDs: [String: UUID] = [:]
        var selectable: [ImportedTransaction] = []
        var imported = 0
        var review = ImportReview()
        let duplicates: BankImportDuplicates.Plan? =
            detectDuplicates && document.tradeRepublic == nil
            ? BankImportDuplicates.plan(rows: document.rows, entries: entries, accountID: checking.account.id)
            : nil
        let directory = accounts + checking.created
        for row in document.rows {
            if row.trade != nil {
                let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
                if entries.contains(where: { entry in
                    guard let fingerprint = entry.importFingerprint else { return false }
                    return fingerprints.contains(fingerprint)
                }) || !known.isDisjoint(with: fingerprints) {
                    known.formUnion(fingerprints)
                    continue
                }
                let entry = ledgerEntry(for: row, checkingID: checking.account.id, portfolioID: portfolio?.account.id)
                context.insert(entry)
                insertedEntries.append(entry)
                entries.append(entry)
                if let trade = row.trade, let portfolio {
                    apply(
                        trade,
                        cashCents: row.amountCents,
                        date: row.date,
                        portfolio: portfolio.account,
                        context: context,
                        holdings: &holdings,
                        insertedHoldings: &insertedHoldings,
                        ledgerEntryID: entry.id
                    )
                }
                known.formUnion(fingerprints)
                imported += 1
                continue
            }
            if let entry = ingestCashRow(
                row,
                checking: checking.account,
                accounts: directory,
                entries: &entries,
                known: &known,
                review: &review,
                detectDuplicates: detectDuplicates,
                duplicates: duplicates,
                context: context
            ) {
                insertedEntries.append(entry)
                selectable.append(row)
                entryIDs[row.fingerprint] = entry.id
                imported += 1
            }
        }
        if checking.account.iban.isEmpty, let iban = document.tradeRepublic?.iban, !iban.isEmpty {
            checking.account.iban = iban
        }
        if let portfolio {
            let closed = holdings.filter { $0.accountID == portfolio.account.id && $0.quantity < 0.0000005 }
            for holding in closed {
                HoldingMaintenance.retire(holding, context: context)
            }
            let closedIDs = Set(closed.map(\.id))
            holdings.removeAll { closedIDs.contains($0.id) }
            insertedHoldings.removeAll { closedIDs.contains($0.id) }
            for holding in holdings where holding.accountID == portfolio.account.id {
                if let position = HoldingMaintenance.averagePurchaseCents(for: HoldingLotStore.lots(for: holding.id)) {
                    holding.purchasePriceCents = position.priceCents
                }
            }
            let plans = SavingsPlanBuilder.build(
                rows: document.rows,
                checkingID: checking.account.id,
                portfolioID: portfolio.account.id,
                holdings: holdings
            )
            SavingsPlanStore.replace(plans, portfolioID: portfolio.account.id)
            SavingsPlanFixedCosts.sync(context: context)
        }
        let portfolioID = portfolio?.account.id
        let holdingCount = holdings.filter { holding in
            holding.accountID == portfolioID && holding.quantity > 0.0000005
        }.count
        var fittedAccountID: UUID?
        if document.tradeRepublic == nil, let currentBalanceCents {
            if review.isEmpty {
                let knownIDs = Set(insertedEntries.map(\.id))
                if let extra = ImportBalance.fitToCurrent(
                    account: checking.account,
                    entries: &entries,
                    currentCents: currentBalanceCents,
                    context: context
                ), !knownIDs.contains(extra.id) {
                    insertedEntries.append(extra)
                }
                fittedAccountID = checking.account.id
            } else {
                review.accountID = checking.account.id
                review.currentCents = currentBalanceCents
            }
        }
        do {
            try context.save()
            if let fittedAccountID, let currentBalanceCents {
                BankImportCursor.mark(fittedAccountID, currentCents: currentBalanceCents)
            }
        } catch {
            insertedEntries.forEach(context.delete)
            insertedHoldings.forEach(context.delete)
            insertedAccounts.forEach(context.delete)
            throw error
        }
        relinkOwnAccounts(context: context)
        return BankImportResult(
            importedCount: imported,
            holdingCount: holdingCount,
            accountName: checking.account.name,
            checkingAccountID: checking.account.id,
            createdSeparateChecking: checking.createdSeparate,
            entryIDs: entryIDs,
            selectableRows: selectable,
            skippedBeforeStart: 0,
            review: review
        )
    }

    static func firstMainAccountPeriod(
        entries: [LedgerEntry],
        accounts: [Account],
        context: ModelContext
    ) -> ForecastPeriod? {
        guard let main = accounts.first(where: \.isMain) else { return nil }
        let dates = entries.compactMap { entry -> Date? in
            guard entryTouches(entry, accountID: main.id) else { return nil }
            return entry.date
        }
        guard let earliest = dates.min() else { return nil }
        let forecasts = (try? context.fetch(FetchDescriptor<IncomeForecast>())) ?? []
        let mode = DashboardPeriodMode(rawValue: AppDefaults.store.string(forKey: "dashboardPeriodMode") ?? "") ?? .calendarMonth
        let primary = mode == .salaryPeriod ? FinancePeriods.primaryForecast(in: forecasts) : nil
        return FinanceService.forecastPeriods(primary: primary, earliest: earliest, latest: earliest).first
    }

    private static func statementBalance(before day: Date, rows: [ImportedTransaction], opening: Int) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        var saldo = opening
        for row in rows {
            guard let printed = row.statementBalanceCents else { continue }
            if calendar.startOfDay(for: row.date) < start {
                saldo = printed
            }
        }
        return saldo
    }

    private static func checkingAccount(
        for document: BankImportDocument,
        destination: BankImportDestination,
        accounts: [Account],
        context: ModelContext
    ) throws -> (account: Account, created: [Account], createdSeparate: Bool) {
        switch destination {
        case .account(let id):
            guard let account = accounts.first(where: { $0.id == id }) else {
                throw BankImportError.missingAccount
            }
            return (account, [], false)
        case .separateChecking:
            let iban = document.tradeRepublic?.iban ?? ""
            if !iban.isEmpty, let existing = accounts.first(where: {
                $0.kind == .checking && $0.iban.replacingOccurrences(of: " ", with: "").uppercased() == iban
            }) {
                return (existing, [], false)
            }
            if document.tradeRepublic != nil, let named = accounts.first(where: {
                $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
            }) {
                if named.iban.trimmingCharacters(in: .whitespaces).isEmpty, !iban.isEmpty {
                    named.iban = iban
                }
                return (named, [], false)
            }
            let account = Account(
                name: document.tradeRepublic == nil ? L("Girokonto", "Checking account") : "Trade Republic",
                kind: .checking,
                isLiquid: true,
                isMain: false,
                iban: iban
            )
            context.insert(account)
            return (account, [account], document.tradeRepublic != nil)
        }
    }

    private static func portfolioAccount(
        for checking: Account,
        document: BankImportDocument,
        context: ModelContext
    ) -> (account: Account, created: [Account])? {
        guard document.tradeRepublic != nil, document.rows.contains(where: { $0.trade != nil }) else { return nil }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let portfolios = accounts.filter { $0.kind == .portfolio }
        if let linked = PortfolioLinkStore.portfolioID(for: checking.id),
           let existing = portfolios.first(where: { $0.id == linked }) {
            existing.isLiquid = false
            return (existing, [])
        }
        if portfolios.count == 1, let only = portfolios.first {
            only.isLiquid = false
            PortfolioLinkStore.link(portfolio: only.id, to: checking.id)
            return (only, [])
        }
        let account = Account(name: L("Depot", "Portfolio"), kind: .portfolio, isLiquid: false)
        context.insert(account)
        PortfolioLinkStore.link(portfolio: account.id, to: checking.id)
        return (account, [account])
    }

    private static func replacePreviousStatement(
        on checkingID: UUID,
        portfolioID: UUID?,
        entries: inout [LedgerEntry],
        holdings: inout [PortfolioHolding],
        context: ModelContext
    ) {
        let doomed = entries.filter { entry in
            entry.importFingerprint != nil
                && entryTouches(entry, accountID: checkingID)
                && (entry.notes.localizedCaseInsensitiveContains("Typ: ")
                    || entry.notes.localizedCaseInsensitiveContains("Type: "))
        }
        guard !doomed.isEmpty else { return }
        let doomedIDs = Set(doomed.map(\.id))
        if let splits = try? context.fetch(FetchDescriptor<TransactionSplit>()) {
            for split in splits where doomedIDs.contains(split.transactionID) {
                context.delete(split)
            }
        }
        doomed.forEach(context.delete)
        entries.removeAll { doomedIDs.contains($0.id) }
        guard let portfolioID else { return }
        let reset = holdings.filter { $0.accountID == portfolioID }
        for holding in reset {
            ClosedPositionStore.remove(isin: holding.symbol)
            HoldingLotStore.removeAll(for: holding.id)
            HoldingPurchaseDateStore.remove(for: holding.id)
            MarketSymbolStore.remove(for: holding.id)
            PreviousCloseStore.remove(for: holding.id)
            context.delete(holding)
        }
        let resetIDs = Set(reset.map(\.id))
        holdings.removeAll { resetIDs.contains($0.id) }
        SavingsPlanStore.removeAll(portfolioID: portfolioID)
    }

    private static func counterpartyAccount(
        for row: ImportedTransaction,
        checking: Account,
        accounts: [Account]
    ) -> Account? {
        guard row.trade == nil else { return nil }
        let raw = row.amountCents >= 0 ? row.senderIBAN : row.recipientIBAN
        let iban = normalizedIBAN(raw)
        let own = normalizedIBAN(checking.iban)
        guard !iban.isEmpty, iban != own else { return nil }
        return accounts.first { account in
            account.id != checking.id
                && account.kind != .portfolio
                && account.kind != .savingsGroup
                && normalizedIBAN(account.iban) == iban
        }
    }

    private static func normalizedIBAN(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func transferExists(
        on date: Date,
        amount: Int,
        first: UUID,
        second: UUID,
        entries: [LedgerEntry]
    ) -> Bool {
        existingTransfer(
            on: date,
            amount: amount,
            first: first,
            second: second,
            entries: entries,
            windowDays: ownAccountWindowDays
        ) != nil
    }

    private static func bookTransfer(
        _ entry: LedgerEntry,
        row: ImportedTransaction,
        checkingID: UUID,
        otherID: UUID,
        entries: inout [LedgerEntry]
    ) {
        if transferExists(on: row.date, amount: row.amountCents, first: checkingID, second: otherID, entries: entries) {
            return
        }
        entry.kind = .transfer
        entry.accountID = nil
        entry.amountCents = abs(row.amountCents)
        if row.amountCents >= 0 {
            entry.fromAccountID = otherID
            entry.toAccountID = checkingID
        } else {
            entry.fromAccountID = checkingID
            entry.toAccountID = otherID
        }
    }

    @discardableResult
    private static func removeMirror(
        of row: ImportedTransaction,
        on accountID: UUID,
        checking: Account,
        entries: inout [LedgerEntry],
        context: ModelContext,
        windowDays: Int = 0
    ) -> Date? {
        let counterparty = normalizedIBAN(row.amountCents >= 0 ? row.senderIBAN : row.recipientIBAN)
        let markers = [counterparty, normalizedIBAN(checking.iban)].filter { !$0.isEmpty }
        guard !markers.isEmpty else { return nil }
        guard let mirror = entries.first(where: { entry in
            guard entry.accountID == accountID else { return false }
            guard entry.kind == .income || entry.kind == .expense else { return false }
            guard abs(entry.amountCents) == abs(row.amountCents) else { return false }
            guard withinDays(entry.date, of: row.date, days: windowDays) else { return false }
            let haystack = normalizedIBAN(entry.notes + " " + entry.title)
            return markers.contains { haystack.contains($0) }
        }) else { return nil }
        let date = mirror.date
        context.delete(mirror)
        entries.removeAll { $0.id == mirror.id }
        return date
    }

    private static func ledgerEntry(for row: ImportedTransaction, checkingID: UUID, portfolioID: UUID?) -> LedgerEntry {
        if row.trade != nil, let portfolioID {
            let amount = abs(row.amountCents)
            if row.amountCents >= 0 {
                return LedgerEntry(
                    date: row.date,
                    title: row.title,
                    notes: row.notes,
                    amountCents: amount,
                    kind: .transfer,
                    fromAccountID: portfolioID,
                    toAccountID: checkingID,
                    importFingerprint: row.fingerprint
                )
            }
            return LedgerEntry(
                date: row.date,
                title: row.title,
                notes: row.notes,
                amountCents: amount,
                kind: .transfer,
                fromAccountID: checkingID,
                toAccountID: portfolioID,
                importFingerprint: row.fingerprint
            )
        }
        return LedgerEntry(
            date: row.date,
            title: row.title,
            notes: row.notes,
            amountCents: row.amountCents,
            kind: row.amountCents < 0 ? .expense : .income,
            accountID: checkingID,
            importFingerprint: row.fingerprint
        )
    }

    private static func apply(
        _ trade: ImportedSecurityTrade,
        cashCents: Int,
        date: Date,
        portfolio: Account,
        context: ModelContext,
        holdings: inout [PortfolioHolding],
        insertedHoldings: inout [PortfolioHolding],
        ledgerEntryID: UUID?
    ) {
        let price = Int((Double(abs(cashCents)) / trade.quantity).rounded())
        let lot = HoldingLot(
            date: date,
            quantity: trade.quantity,
            unitPriceCents: max(price, 0),
            amountCents: cashCents,
            isSale: trade.isSale,
            isSavingsPlan: trade.isSavingsPlan,
            ledgerEntryID: ledgerEntryID
        )
        if trade.isSale {
            guard let holding = holdings.first(where: { $0.accountID == portfolio.id && $0.symbol.caseInsensitiveCompare(trade.isin) == .orderedSame }) else { return }
            HoldingLotStore.add(lot, holdingID: holding.id)
            holding.quantity = max(0, holding.quantity - trade.quantity)
            holding.currentPriceCents = max(price, 0)
            holding.updatedAt = .now
            return
        }
        if let holding = holdings.first(where: { $0.accountID == portfolio.id && $0.symbol.caseInsensitiveCompare(trade.isin) == .orderedSame }) {
            let previous = holding.quantity * Double(holding.purchasePriceCents)
            let next = holding.quantity + trade.quantity
            holding.purchasePriceCents = Int(((previous + Double(abs(cashCents))) / next).rounded())
            holding.quantity = next
            holding.currentPriceCents = max(price, 0)
            holding.name = trade.name
            holding.updatedAt = .now
            HoldingLotStore.add(lot, holdingID: holding.id)
            rememberPurchase(date, holdingID: holding.id)
            return
        }
        let holding = PortfolioHolding(
            accountID: portfolio.id,
            name: trade.name,
            symbol: trade.isin,
            quantity: trade.quantity,
            purchasePriceCents: max(price, 0),
            currentPriceCents: max(price, 0),
            updatedAt: date
        )
        context.insert(holding)
        holdings.append(holding)
        insertedHoldings.append(holding)
        HoldingLotStore.add(lot, holdingID: holding.id)
        HoldingPurchaseDateStore.set(date, for: holding.id)
    }

    private static func rememberPurchase(_ date: Date, holdingID: UUID) {
        if let existing = HoldingPurchaseDateStore.date(for: holdingID), existing <= date { return }
        HoldingPurchaseDateStore.set(date, for: holdingID)
    }

    private static func entryTouches(_ entry: LedgerEntry, accountID: UUID) -> Bool {
        entry.accountID == accountID || entry.fromAccountID == accountID || entry.toAccountID == accountID
    }

    @discardableResult
    static func ingestCashRow(
        _ row: ImportedTransaction,
        checking: Account,
        accounts: [Account],
        entries: inout [LedgerEntry],
        known: inout Set<String>,
        review: inout ImportReview,
        detectDuplicates: Bool = true,
        duplicates: BankImportDuplicates.Plan? = nil,
        context: ModelContext
    ) -> LedgerEntry? {
        if known.contains(row.fingerprint) {
            return nil
        }
        if detectDuplicates {
            if entries.contains(where: { $0.importFingerprint == row.fingerprint }) {
                known.insert(row.fingerprint)
                return nil
            }
            if let legacy = row.legacyFingerprint,
               let existing = entries.first(where: { $0.importFingerprint == legacy }) {
                let purpose = BankImportService.purposeMark(notes: row.notes)
                if purpose.isEmpty || existing.notes.contains(purpose) {
                    existing.importFingerprint = row.fingerprint
                    known.insert(row.fingerprint)
                    return nil
                }
            }
        }

        if let other = counterpartyAccount(for: row, checking: checking, accounts: accounts) {
            if transferExists(on: row.date, amount: row.amountCents, first: checking.id, second: other.id, entries: entries)
                || existingTransfer(
                    on: row.date,
                    amount: row.amountCents,
                    first: checking.id,
                    second: other.id,
                    entries: entries,
                    windowDays: 3
                ) != nil {
                known.insert(row.fingerprint)
                return nil
            }
            let entry = ledgerEntry(for: row, checkingID: checking.id, portfolioID: nil)
            context.insert(entry)
            entries.append(entry)
            known.insert(row.fingerprint)
            bookTransfer(entry, row: row, checkingID: checking.id, otherID: other.id, entries: &entries)
            if let mirrorDate = removeMirror(of: row, on: other.id, checking: checking, entries: &entries, context: context, windowDays: 3),
               mirrorDate < entry.date {
                entry.date = mirrorDate
            }
            return entry
        }

        if detectDuplicates, let duplicates {
            if duplicates.shouldSkip(row.fingerprint) {
                known.insert(row.fingerprint)
                return nil
            }
            if let choice = duplicates.reviewChoice(for: row.fingerprint) {
                review.similar.append(choice)
                known.insert(row.fingerprint)
                return nil
            }
        } else if detectDuplicates, let existing = similarMatch(row: row, entries: entries, accountID: checking.id) {
            let rowPurpose = BankImportService.purposeMark(notes: row.notes)
            if !rowPurpose.isEmpty, existing.notes.contains(rowPurpose) {
                existing.importFingerprint = row.fingerprint
                known.insert(row.fingerprint)
                return nil
            }
            review.similar.append(similarChoice(row: row, existing: existing, accountID: checking.id))
            known.insert(row.fingerprint)
            return nil
        }

        let entry = ledgerEntry(for: row, checkingID: checking.id, portfolioID: nil)
        context.insert(entry)
        entries.append(entry)
        known.insert(row.fingerprint)
        return entry
    }

    static func commitReview(_ review: ImportReview, context: ModelContext) throws {
        var entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        for choice in review.transfers where choice.accept {
            guard let entry = entries.first(where: { $0.id == choice.entryID }),
                  let checking = accounts.first(where: { $0.id == choice.checkingAccountID })
            else { continue }
            let inbound = choice.signedAmountCents >= 0
            let row = ImportedTransaction(
                date: choice.date,
                title: choice.title,
                notes: choice.notes,
                amountCents: choice.signedAmountCents,
                iban: choice.iban,
                senderIBAN: inbound ? choice.iban : "",
                recipientIBAN: inbound ? "" : choice.iban,
                fingerprint: entry.importFingerprint ?? choice.entryID.uuidString
            )
            if transferExists(
                on: choice.date,
                amount: choice.signedAmountCents,
                first: choice.checkingAccountID,
                second: choice.otherAccountID,
                entries: entries
            ) {
                context.delete(entry)
                entries.removeAll { $0.id == entry.id }
                continue
            }
            bookTransfer(
                entry,
                row: row,
                checkingID: choice.checkingAccountID,
                otherID: choice.otherAccountID,
                entries: &entries
            )
            var earliest = choice.date
            if let mirror = entries.first(where: { $0.id == choice.matchedEntryID }),
               mirror.id != entry.id,
               mirror.kind == .income || mirror.kind == .expense {
                earliest = min(earliest, mirror.date)
                context.delete(mirror)
                entries.removeAll { $0.id == mirror.id }
            }
            if let mirrorDate = removeMirror(
                of: row,
                on: choice.otherAccountID,
                checking: checking,
                entries: &entries,
                context: context,
                windowDays: 3
            ) {
                earliest = min(earliest, mirrorDate)
            }
            entry.date = earliest
        }
        for choice in review.similar where choice.include {
            let entry = LedgerEntry(
                date: choice.date,
                title: choice.title,
                notes: choice.notes,
                amountCents: choice.signedAmountCents,
                kind: choice.signedAmountCents < 0 ? .expense : .income,
                accountID: choice.accountID,
                importFingerprint: choice.fingerprint
            )
            context.insert(entry)
            entries.append(entry)
        }
        if let accountID = review.accountID,
           let cents = review.currentCents,
           let account = accounts.first(where: { $0.id == accountID }) {
            _ = ImportBalance.fitToCurrent(
                account: account,
                entries: &entries,
                currentCents: cents,
                context: context
            )
        }
        try context.save()
        relinkOwnAccounts(context: context)
        if let accountID = review.accountID, let cents = review.currentCents {
            BankImportCursor.mark(accountID, currentCents: cents)
        }
    }

    /// Own-account transfers can land a banking day or two later than they left.
    static let ownAccountWindowDays = 3

    /// A booking between two of your own accounts is a transfer. Combined it is neutral.
    /// On the sending account it leaves, and on the receiving account it arrives.
    /// Two cash bookings on the same day with the same amount both stay.
    static func relinkOwnAccounts(context: ModelContext) {
        guard var entries = try? context.fetch(FetchDescriptor<LedgerEntry>()) else { return }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        rememberTradeRepublicIBAN(entries: entries, accounts: accounts)
        let checking = accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
        let checkingIDs = Set(checking.map(\.id))
        let withIBAN = checking.filter { !normalizedIBAN($0.iban).isEmpty }
        var changed = false
        if withIBAN.count > 1 {
            for entry in entries where entry.kind == .income || entry.kind == .expense {
                guard let accountID = entry.accountID else { continue }
                let parsed = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents)
                let counterparty = normalizedIBAN(entry.amountCents >= 0 ? parsed.sender : parsed.recipient)
                guard !counterparty.isEmpty,
                      let other = withIBAN.first(where: { $0.id != accountID && normalizedIBAN($0.iban) == counterparty })
                else { continue }
                if let existing = existingTransfer(
                    on: entry.date,
                    amount: entry.amountCents,
                    first: accountID,
                    second: other.id,
                    entries: entries,
                    windowDays: ownAccountWindowDays
                ) {
                    if entry.date < existing.date { existing.date = entry.date }
                    context.delete(entry)
                    entries.removeAll { $0.id == entry.id }
                    changed = true
                    continue
                }
                let inbound = entry.amountCents >= 0
                let row = ImportedTransaction(
                    date: entry.date,
                    title: entry.title,
                    notes: entry.notes,
                    amountCents: entry.amountCents,
                    iban: counterparty,
                    senderIBAN: inbound ? counterparty : "",
                    recipientIBAN: inbound ? "" : counterparty,
                    fingerprint: entry.importFingerprint ?? entry.id.uuidString
                )
                bookTransfer(entry, row: row, checkingID: accountID, otherID: other.id, entries: &entries)
                if let source = accounts.first(where: { $0.id == accountID }) {
                    if let mirrorDate = removeMirror(of: row, on: other.id, checking: source, entries: &entries, context: context, windowDays: 3),
                       mirrorDate < entry.date {
                        entry.date = mirrorDate
                    }
                }
                changed = true
            }
        }
        if collapseTransferMirrors(entries: &entries, checkingIDs: checkingIDs, context: context) {
            changed = true
        }
        if mergeNamedTradeRepublicMoves(entries: &entries, accounts: checking, context: context) {
            changed = true
        }
        guard changed else { return }
        try? context.save()
    }

    /// An income or expense that already has a matching own-account transfer is the same payment twice.
    private static func collapseTransferMirrors(
        entries: inout [LedgerEntry],
        checkingIDs: Set<UUID>,
        context: ModelContext
    ) -> Bool {
        var changed = false
        for entry in entries where entry.kind == .income || entry.kind == .expense {
            guard let accountID = entry.accountID, checkingIDs.contains(accountID) else { continue }
            let matches = entries.filter { transfer in
                guard transfer.kind == .transfer, abs(transfer.amountCents) == abs(entry.amountCents) else {
                    return false
                }
                guard withinDays(transfer.date, of: entry.date, days: ownAccountWindowDays) else { return false }
                let ends = Set([transfer.fromAccountID, transfer.toAccountID].compactMap { $0 })
                return ends.contains(accountID) && ends.contains(where: { checkingIDs.contains($0) && $0 != accountID })
            }
            guard !matches.isEmpty else { continue }
            let earliest = ([entry.date] + matches.map(\.date)).min() ?? entry.date
            for transfer in matches where transfer.date > earliest {
                transfer.date = earliest
            }
            context.delete(entry)
            entries.removeAll { $0.id == entry.id }
            changed = true
        }
        return changed
    }

    /// A payment that names Trade Republic on one account and lands as cash on Trade Republic is one transfer.
    private static func mergeNamedTradeRepublicMoves(
        entries: inout [LedgerEntry],
        accounts: [Account],
        context: ModelContext
    ) -> Bool {
        guard let tradeRepublic = accounts.first(where: {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }) else { return false }
        var changed = false
        for entry in entries where entry.kind == .income || entry.kind == .expense {
            guard let accountID = entry.accountID, accountID != tradeRepublic.id else { continue }
            guard mentionsTradeRepublic(entry) else { continue }
            let matches = entries.filter { other in
                guard other.id != entry.id else { return false }
                guard other.accountID == tradeRepublic.id, other.kind == .income || other.kind == .expense else {
                    return false
                }
                guard abs(other.amountCents) == abs(entry.amountCents) else { return false }
                return withinDays(other.date, of: entry.date, days: ownAccountWindowDays)
            }
            if let existing = existingTransfer(
                on: entry.date,
                amount: entry.amountCents,
                first: accountID,
                second: tradeRepublic.id,
                entries: entries,
                windowDays: ownAccountWindowDays
            ) {
                let earliest = ([entry.date, existing.date] + matches.map(\.date)).min() ?? entry.date
                existing.date = earliest
                context.delete(entry)
                entries.removeAll { $0.id == entry.id }
                for match in matches {
                    context.delete(match)
                    entries.removeAll { $0.id == match.id }
                }
                changed = true
                continue
            }
            let earliest = ([entry.date] + matches.map(\.date)).min() ?? entry.date
            let row = ImportedTransaction(
                date: earliest,
                title: entry.title,
                notes: entry.notes,
                amountCents: entry.amountCents,
                iban: "",
                senderIBAN: "",
                recipientIBAN: "",
                fingerprint: entry.importFingerprint ?? entry.id.uuidString
            )
            bookTransfer(entry, row: row, checkingID: accountID, otherID: tradeRepublic.id, entries: &entries)
            entry.date = earliest
            for match in matches {
                context.delete(match)
                entries.removeAll { $0.id == match.id }
            }
            changed = true
        }
        return changed
    }

    private static func mentionsTradeRepublic(_ entry: LedgerEntry) -> Bool {
        "\(entry.title)\n\(entry.notes)"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .contains("trade republic")
    }

    /// A booking that names Trade Republic and already shows the other account's IBAN
    /// fills the empty Trade Republic IBAN, so the payment can become a transfer.
    private static func rememberTradeRepublicIBAN(entries: [LedgerEntry], accounts: [Account]) {
        guard let tradeRepublic = accounts.first(where: {
            $0.kind == .checking
                && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
                && normalizedIBAN($0.iban).isEmpty
        }) else { return }
        let owned = Set(accounts.compactMap { account -> String? in
            let value = normalizedIBAN(account.iban)
            return value.isEmpty ? nil : value
        })
        for entry in entries {
            let text = "\(entry.title)\n\(entry.notes)"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            guard text.contains("trade republic") else { continue }
            let parsed = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents)
            let sender = normalizedIBAN(parsed.sender)
            let recipient = normalizedIBAN(parsed.recipient)
            guard !sender.isEmpty, !recipient.isEmpty, sender != recipient else { continue }
            let candidate: String
            if owned.contains(sender), !owned.contains(recipient) {
                candidate = recipient
            } else if owned.contains(recipient), !owned.contains(sender) {
                candidate = sender
            } else {
                continue
            }
            tradeRepublic.iban = candidate
            return
        }
    }

    private static func transferChoice(
        entry: LedgerEntry,
        row: ImportedTransaction,
        checking: Account,
        other: Account,
        match: LedgerEntry
    ) -> ImportTransferChoice {
        let iban = normalizedIBAN(row.amountCents >= 0 ? row.senderIBAN : row.recipientIBAN)
        return ImportTransferChoice(
            entryID: entry.id,
            signedAmountCents: row.amountCents,
            date: row.date,
            title: row.title,
            notes: row.notes,
            checkingAccountID: checking.id,
            otherAccountID: other.id,
            otherAccountName: other.name,
            iban: iban,
            matchedEntryID: match.id,
            matchedTitle: match.title,
            matchedDate: match.date,
            matchedAmountCents: match.amountCents
        )
    }

    private static func similarChoice(
        row: ImportedTransaction,
        existing: LedgerEntry,
        accountID: UUID
    ) -> ImportSimilarChoice {
        ImportSimilarChoice(
            id: UUID(),
            fingerprint: row.fingerprint,
            date: row.date,
            title: row.title,
            notes: row.notes,
            signedAmountCents: row.amountCents,
            accountID: accountID,
            existingTitle: existing.title,
            existingDate: existing.date,
            existingAmountCents: existing.amountCents
        )
    }

    private static func transferMatch(
        row: ImportedTransaction,
        other: Account,
        entries: [LedgerEntry]
    ) -> LedgerEntry? {
        let amount = abs(row.amountCents)
        return entries.first { entry in
            guard abs(entry.amountCents) == amount else { return false }
            guard withinDays(entry.date, of: row.date, days: 3) else { return false }
            if entry.accountID == other.id || entry.fromAccountID == other.id || entry.toAccountID == other.id {
                return true
            }
            return sharesIBAN(row, entry: entry)
        }
    }

    private static func similarMatch(
        row: ImportedTransaction,
        entries: [LedgerEntry],
        accountID: UUID
    ) -> LedgerEntry? {
        let amount = abs(row.amountCents)
        let rowPurpose = BankImportService.purposeMark(notes: row.notes)
        return entries.first { entry in
            guard entry.kind != .adjustment else { return false }
            guard entry.accountID == accountID else { return false }
            guard abs(entry.amountCents) == amount else { return false }
            guard withinDays(entry.date, of: row.date, days: 3) else { return false }
            guard payeesMatch(row.title, entry.title) else { return false }
            if !rowPurpose.isEmpty, !entry.notes.contains(rowPurpose) { return false }
            return true
        }
    }

    /// The shop or payee, without the place that Sparkasse appends after a slash.
    private static func payeesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = payeeKey(lhs)
        let right = payeeKey(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        if left == right { return true }
        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        return shorter.count >= 8 && longer.hasPrefix(shorter)
    }

    private static func payeeKey(_ title: String) -> String {
        let head = title.split(whereSeparator: { $0 == "/" || $0 == "|" }).first.map(String.init) ?? title
        let folded = head.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }

    private static func existingTransfer(
        on date: Date,
        amount: Int,
        first: UUID,
        second: UUID,
        entries: [LedgerEntry],
        windowDays: Int
    ) -> LedgerEntry? {
        let absAmount = abs(amount)
        return entries.first { entry in
            guard entry.kind == .transfer, abs(entry.amountCents) == absAmount else { return false }
            guard withinDays(entry.date, of: date, days: windowDays) else { return false }
            let ends = Set([entry.fromAccountID, entry.toAccountID].compactMap { $0 })
            return ends == [first, second]
        }
    }

    private static func withinDays(_ date: Date, of other: Date, days: Int) -> Bool {
        let calendar = Calendar.current
        let delta = abs(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: other)
        ).day ?? 0)
        return delta <= days
    }

    private static func sharesIBAN(_ row: ImportedTransaction, entry: LedgerEntry) -> Bool {
        let candidates = [row.senderIBAN, row.recipientIBAN, row.iban]
            .map(normalizedIBAN)
            .filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return false }
        let parsed = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents)
        let known = [parsed.sender, parsed.recipient].map(normalizedIBAN).filter { !$0.isEmpty }
        if candidates.contains(where: known.contains) { return true }
        let haystack = normalizedIBAN(entry.notes + " " + entry.title)
        return candidates.contains { haystack.contains($0) }
    }
}
