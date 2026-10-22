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

enum PortfolioLinkStore {
    private static func key(for checkingID: UUID) -> String {
        "lifify.portfolioLink.\(checkingID.uuidString)"
    }

    static func portfolioID(for checkingID: UUID) -> UUID? {
        UserDefaults.standard.string(forKey: key(for: checkingID)).flatMap(UUID.init(uuidString:))
    }

    static func link(portfolio portfolioID: UUID, to checkingID: UUID) {
        unlink(portfolio: portfolioID)
        UserDefaults.standard.set(portfolioID.uuidString, forKey: key(for: checkingID))
    }

    static func checkingID(for portfolioID: UUID) -> UUID? {
        let prefix = "lifify.portfolioLink."
        let target = portfolioID.uuidString
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            guard key.hasPrefix(prefix), (value as? String) == target else { continue }
            return UUID(uuidString: String(key.dropFirst(prefix.count)))
        }
        return nil
    }

    static func unlink(checkingID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: checkingID))
    }

    static func unlink(portfolio portfolioID: UUID) {
        let prefix = "lifify.portfolioLink."
        let target = portfolioID.uuidString
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            guard key.hasPrefix(prefix), (value as? String) == target else { continue }
            UserDefaults.standard.removeObject(forKey: key)
        }
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
        openingBalanceCents: Int?,
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

        if document.tradeRepublic == nil, let openingBalanceCents,
           !entries.contains(where: { $0.kind == .adjustment && $0.accountID == checking.account.id }),
           let firstDate = document.rows.map(\.date).min() {
            let adjustment = LedgerEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: firstDate) ?? firstDate,
                title: L("Eröffnungssaldo", "Opening balance"),
                amountCents: openingBalanceCents,
                kind: .adjustment,
                accountID: checking.account.id
            )
            context.insert(adjustment)
            insertedEntries.append(adjustment)
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
        var skippedBeforeStart = 0
        var review = ImportReview()
        let directory = accounts + checking.created
        let periodStart = period.map { Calendar.current.startOfDay(for: $0.start) }
        for row in document.rows {
            if let periodStart, Calendar.current.startOfDay(for: row.date) < periodStart {
                if let trade = row.trade, let portfolio {
                    apply(
                        trade,
                        cashCents: row.amountCents,
                        date: row.date,
                        portfolio: portfolio.account,
                        context: context,
                        holdings: &holdings,
                        insertedHoldings: &insertedHoldings,
                        ledgerEntryID: nil
                    )
                }
                skippedBeforeStart += 1
                continue
            }
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
        do {
            try context.save()
        } catch {
            insertedEntries.forEach(context.delete)
            insertedHoldings.forEach(context.delete)
            insertedAccounts.forEach(context.delete)
            throw error
        }
        return BankImportResult(
            importedCount: imported,
            holdingCount: holdingCount,
            accountName: checking.account.name,
            checkingAccountID: checking.account.id,
            createdSeparateChecking: checking.createdSeparate,
            entryIDs: entryIDs,
            selectableRows: selectable,
            skippedBeforeStart: skippedBeforeStart,
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
            guard entry.kind != .adjustment, entryTouches(entry, accountID: main.id) else { return nil }
            return entry.date
        }
        guard let earliest = dates.min() else { return nil }
        let forecasts = (try? context.fetch(FetchDescriptor<IncomeForecast>())) ?? []
        let mode = DashboardPeriodMode(rawValue: UserDefaults.standard.string(forKey: "dashboardPeriodMode") ?? "") ?? .calendarMonth
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
        let day = Calendar.current.startOfDay(for: date)
        let absAmount = abs(amount)
        return entries.contains { entry in
            guard entry.kind == .transfer, abs(entry.amountCents) == absAmount else { return false }
            guard Calendar.current.startOfDay(for: entry.date) == day else { return false }
            let ends = Set([entry.fromAccountID, entry.toAccountID].compactMap { $0 })
            return ends == [first, second]
        }
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

    private static func removeMirror(
        of row: ImportedTransaction,
        on accountID: UUID,
        checking: Account,
        entries: inout [LedgerEntry],
        context: ModelContext,
        windowDays: Int = 0
    ) {
        let counterparty = normalizedIBAN(row.amountCents >= 0 ? row.senderIBAN : row.recipientIBAN)
        let markers = [counterparty, normalizedIBAN(checking.iban)].filter { !$0.isEmpty }
        guard !markers.isEmpty else { return }
        guard let mirror = entries.first(where: { entry in
            guard entry.accountID == accountID else { return false }
            guard entry.kind == .income || entry.kind == .expense else { return false }
            guard abs(entry.amountCents) == abs(row.amountCents) else { return false }
            guard withinDays(entry.date, of: row.date, days: windowDays) else { return false }
            let haystack = normalizedIBAN(entry.notes + " " + entry.title)
            return markers.contains { haystack.contains($0) }
        }) else { return }
        context.delete(mirror)
        entries.removeAll { $0.id == mirror.id }
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
        context: ModelContext
    ) -> LedgerEntry? {
        let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
        if let existing = entries.first(where: { entry in
            guard let fingerprint = entry.importFingerprint else { return false }
            return fingerprints.contains(fingerprint)
        }) {
            review.similar.append(similarChoice(row: row, existing: existing, accountID: checking.id))
            known.formUnion(fingerprints)
            return nil
        }
        guard known.isDisjoint(with: fingerprints) else { return nil }

        if let other = counterpartyAccount(for: row, checking: checking, accounts: accounts) {
            if let existing = existingTransfer(
                on: row.date,
                amount: row.amountCents,
                first: checking.id,
                second: other.id,
                entries: entries,
                windowDays: 3
            ) {
                review.similar.append(similarChoice(row: row, existing: existing, accountID: checking.id))
                known.formUnion(fingerprints)
                return nil
            }
            if let match = transferMatch(row: row, other: other, entries: entries) {
                let entry = ledgerEntry(for: row, checkingID: checking.id, portfolioID: nil)
                context.insert(entry)
                entries.append(entry)
                known.formUnion(fingerprints)
                review.transfers.append(transferChoice(entry: entry, row: row, checking: checking, other: other, match: match))
                return entry
            }
        }

        if let existing = similarMatch(row: row, entries: entries) {
            review.similar.append(similarChoice(row: row, existing: existing, accountID: checking.id))
            known.formUnion(fingerprints)
            return nil
        }

        let entry = ledgerEntry(for: row, checkingID: checking.id, portfolioID: nil)
        context.insert(entry)
        entries.append(entry)
        known.formUnion(fingerprints)
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
            if let mirror = entries.first(where: { $0.id == choice.matchedEntryID }),
               mirror.id != entry.id,
               mirror.kind == .income || mirror.kind == .expense {
                context.delete(mirror)
                entries.removeAll { $0.id == mirror.id }
            }
            removeMirror(
                of: row,
                on: choice.otherAccountID,
                checking: checking,
                entries: &entries,
                context: context,
                windowDays: 3
            )
        }
        for choice in review.similar where choice.include {
            context.insert(LedgerEntry(
                date: choice.date,
                title: choice.title,
                notes: choice.notes,
                amountCents: choice.signedAmountCents,
                kind: choice.signedAmountCents < 0 ? .expense : .income,
                accountID: choice.accountID,
                importFingerprint: choice.fingerprint
            ))
        }
        try context.save()
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

    private static func similarMatch(row: ImportedTransaction, entries: [LedgerEntry]) -> LedgerEntry? {
        let amount = abs(row.amountCents)
        return entries.first { entry in
            guard entry.kind != .adjustment else { return false }
            guard abs(entry.amountCents) == amount else { return false }
            guard withinDays(entry.date, of: row.date, days: 3) else { return false }
            return titlesMatch(row.title, entry.title) || sharesIBAN(row, entry: entry)
        }
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

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
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
