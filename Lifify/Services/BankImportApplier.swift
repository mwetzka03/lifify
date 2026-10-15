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
}

enum PortfolioLinkStore {
    private static func key(for checkingID: UUID) -> String {
        "lifify.portfolioLink.\(checkingID.uuidString)"
    }

    static func portfolioID(for checkingID: UUID) -> UUID? {
        UserDefaults.standard.string(forKey: key(for: checkingID)).flatMap(UUID.init(uuidString:))
    }

    static func link(portfolio portfolioID: UUID, to checkingID: UUID) {
        UserDefaults.standard.set(portfolioID.uuidString, forKey: key(for: checkingID))
    }
}

@MainActor
enum PortfolioConsolidation {
    static func consolidate(context: ModelContext) {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let portfolios = accounts.filter { $0.kind == .portfolio }
        guard !portfolios.isEmpty, let primary = primaryPortfolio(in: portfolios) else { return }
        var changed = false
        for portfolio in portfolios where portfolio.isLiquid {
            portfolio.isLiquid = false
            changed = true
        }
        let generatedOnly = portfolios.allSatisfy { $0.id == primary.id || isGeneratedName($0.name) }
        if generatedOnly, isGeneratedName(primary.name) {
            primary.name = L("Depot", "Portfolio")
            changed = true
        }
        let extras = portfolios.filter { $0.id != primary.id && isGeneratedName($0.name) }
        if !extras.isEmpty {
            let extraIDs = Set(extras.map(\.id))
            let holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
            for holding in holdings where holding.accountID.map({ extraIDs.contains($0) }) == true {
                context.delete(holding)
            }
            extras.forEach(context.delete)
            changed = true
        }
        if changed { try? context.save() }
    }

    static func primaryPortfolio(in portfolios: [Account]) -> Account? {
        let named = portfolios.filter { !isGeneratedName($0.name) }.sorted { $0.createdAt < $1.createdAt }
        if let first = named.first { return first }
        return portfolios.min { $0.createdAt < $1.createdAt }
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
                rows: document.rows,
                entries: &entries,
                holdings: &holdings,
                context: context
            )
        }

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
        let directory = accounts + checking.created
        for row in document.rows {
            let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
            let other = counterpartyAccount(for: row, checking: checking.account, accounts: directory)
            if let existing = entries.first(where: { entry in
                guard let fingerprint = entry.importFingerprint else { return false }
                return fingerprints.contains(fingerprint)
            }) {
                if let other, existing.kind != .transfer, row.trade == nil {
                    if transferExists(on: row.date, amount: row.amountCents, first: checking.account.id, second: other.id, entries: entries) {
                        context.delete(existing)
                        entries.removeAll { $0.id == existing.id }
                    } else {
                        bookTransfer(existing, row: row, checkingID: checking.account.id, otherID: other.id, entries: &entries)
                    }
                } else if row.trade == nil, other == nil {
                    selectable.append(row)
                    entryIDs[row.fingerprint] = existing.id
                }
                known.formUnion(fingerprints)
                continue
            }
            guard known.isDisjoint(with: fingerprints) else { continue }
            if let other {
                if transferExists(on: row.date, amount: row.amountCents, first: checking.account.id, second: other.id, entries: entries) {
                    known.formUnion(fingerprints)
                    continue
                }
                removeMirror(of: row, on: other.id, checking: checking.account, entries: &entries, context: context)
                let entry = transferEntry(for: row, checkingID: checking.account.id, otherID: other.id)
                context.insert(entry)
                insertedEntries.append(entry)
                entries.append(entry)
                known.formUnion(fingerprints)
                imported += 1
                continue
            }
            let entry = ledgerEntry(for: row, checkingID: checking.account.id, portfolioID: portfolio?.account.id)
            context.insert(entry)
            insertedEntries.append(entry)
            entries.append(entry)
            if let trade = row.trade, let portfolio {
                apply(trade, cashCents: row.amountCents, portfolio: portfolio.account, context: context, holdings: &holdings, insertedHoldings: &insertedHoldings)
            }
            known.formUnion(fingerprints)
            if row.trade == nil {
                selectable.append(row)
                entryIDs[row.fingerprint] = entry.id
            }
            imported += 1
        }
        if checking.account.iban.isEmpty, let iban = document.tradeRepublic?.iban, !iban.isEmpty {
            checking.account.iban = iban
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
            selectableRows: selectable
        )
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
        if let primary = PortfolioConsolidation.primaryPortfolio(in: portfolios) {
            primary.isLiquid = false
            PortfolioLinkStore.link(portfolio: primary.id, to: checking.id)
            return (primary, [])
        }
        let account = Account(name: L("Depot", "Portfolio"), kind: .portfolio, isLiquid: false)
        context.insert(account)
        PortfolioLinkStore.link(portfolio: account.id, to: checking.id)
        return (account, [account])
    }

    private static func replacePreviousStatement(
        on checkingID: UUID,
        portfolioID: UUID?,
        rows: [ImportedTransaction],
        entries: inout [LedgerEntry],
        holdings: inout [PortfolioHolding],
        context: ModelContext
    ) {
        let doomed = entries.filter { entry in
            entry.importFingerprint != nil
                && entryTouches(entry, accountID: checkingID)
                && entry.notes.localizedCaseInsensitiveContains("Typ: ")
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
        let isins = Set(rows.compactMap { $0.trade?.isin.uppercased() })
        guard let portfolioID, !isins.isEmpty else { return }
        let reset = holdings.filter { holding in
            holding.accountID == portfolioID && isins.contains(holding.symbol.uppercased())
        }
        reset.forEach(context.delete)
        let resetIDs = Set(reset.map(\.id))
        holdings.removeAll { resetIDs.contains($0.id) }
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
        context: ModelContext
    ) {
        let counterparty = normalizedIBAN(row.amountCents >= 0 ? row.senderIBAN : row.recipientIBAN)
        let markers = [counterparty, normalizedIBAN(checking.iban)].filter { !$0.isEmpty }
        guard !markers.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: row.date)
        guard let mirror = entries.first(where: { entry in
            guard entry.accountID == accountID else { return false }
            guard entry.kind == .income || entry.kind == .expense else { return false }
            guard abs(entry.amountCents) == abs(row.amountCents) else { return false }
            guard Calendar.current.startOfDay(for: entry.date) == day else { return false }
            let haystack = normalizedIBAN(entry.notes + " " + entry.title)
            return markers.contains { haystack.contains($0) }
        }) else { return }
        context.delete(mirror)
        entries.removeAll { $0.id == mirror.id }
    }

    private static func transferEntry(for row: ImportedTransaction, checkingID: UUID, otherID: UUID) -> LedgerEntry {
        let inbound = row.amountCents >= 0
        return LedgerEntry(
            date: row.date,
            title: row.title,
            notes: row.notes,
            amountCents: abs(row.amountCents),
            kind: .transfer,
            fromAccountID: inbound ? otherID : checkingID,
            toAccountID: inbound ? checkingID : otherID,
            importFingerprint: row.fingerprint
        )
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
        portfolio: Account,
        context: ModelContext,
        holdings: inout [PortfolioHolding],
        insertedHoldings: inout [PortfolioHolding]
    ) {
        let price = Int((Double(abs(cashCents)) / trade.quantity).rounded())
        if trade.isSale {
            guard let holding = holdings.first(where: { $0.accountID == portfolio.id && $0.symbol.caseInsensitiveCompare(trade.isin) == .orderedSame }) else { return }
            holding.quantity = max(0, holding.quantity - trade.quantity)
            holding.currentPriceCents = max(price, 0)
            holding.updatedAt = .now
            if holding.quantity < 0.0000005 {
                context.delete(holding)
                holdings.removeAll { $0.id == holding.id }
                insertedHoldings.removeAll { $0.id == holding.id }
            }
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
            return
        }
        let holding = PortfolioHolding(
            accountID: portfolio.id,
            name: trade.name,
            symbol: trade.isin,
            quantity: trade.quantity,
            purchasePriceCents: max(price, 0),
            currentPriceCents: max(price, 0)
        )
        context.insert(holding)
        holdings.append(holding)
        insertedHoldings.append(holding)
    }

    private static func entryTouches(_ entry: LedgerEntry, accountID: UUID) -> Bool {
        entry.accountID == accountID || entry.fromAccountID == accountID || entry.toAccountID == accountID
    }
}
