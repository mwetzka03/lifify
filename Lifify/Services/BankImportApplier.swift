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
enum BankImportApplier {
    static func apply(
        document: BankImportDocument,
        to destination: BankImportDestination,
        openingBalanceCents: Int?,
        context: ModelContext
    ) throws -> BankImportResult {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let entries = try context.fetch(FetchDescriptor<LedgerEntry>())
        var holdings = try context.fetch(FetchDescriptor<PortfolioHolding>())
        let checking = try checkingAccount(for: document, destination: destination, accounts: accounts, context: context)
        let portfolio = portfolioAccount(for: checking.account, document: document, context: context)
        var insertedEntries: [LedgerEntry] = []
        var insertedHoldings: [PortfolioHolding] = []
        let insertedAccounts = checking.created + (portfolio?.created ?? [])

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
        for row in document.rows {
            let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
            if let existing = entries.first(where: { entry in
                guard let fingerprint = entry.importFingerprint else { return false }
                return fingerprints.contains(fingerprint)
            }) {
                selectable.append(row)
                entryIDs[row.fingerprint] = existing.id
                known.formUnion(fingerprints)
                continue
            }
            guard known.isDisjoint(with: fingerprints) else { continue }
            let entry = ledgerEntry(for: row, checkingID: checking.account.id, portfolioID: portfolio?.account.id)
            context.insert(entry)
            insertedEntries.append(entry)
            if let trade = row.trade, let portfolio {
                apply(trade, cashCents: row.amountCents, portfolio: portfolio.account, context: context, holdings: &holdings, insertedHoldings: &insertedHoldings)
            }
            known.formUnion(fingerprints)
            selectable.append(row)
            entryIDs[row.fingerprint] = entry.id
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
        if let linked = PortfolioLinkStore.portfolioID(for: checking.id),
           let existing = accounts.first(where: { $0.id == linked && $0.kind == .portfolio }) {
            return (existing, [])
        }
        let account = Account(
            name: "\(L("Depot", "Portfolio")) · \(checking.name)",
            kind: .portfolio,
            isLiquid: false
        )
        context.insert(account)
        PortfolioLinkStore.link(portfolio: account.id, to: checking.id)
        return (account, [account])
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
