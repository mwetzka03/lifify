import Foundation
import LififyCore
import SwiftData

/// Writes a Trade Republic snapshot into accounts, holdings, and bookings.
@MainActor
public enum TradeRepublicDepotApplier {
    /// Brings the depot and the Trade Republic checking account in line with one session.
    /// A later sign-in replaces the previous Trade Republic lots, holdings, and session bookings.
    /// Own-account transfers that did not come from that session stay.
    ///
    /// - Parameters:
    ///   - snapshot: The data loaded in the session.
    ///   - context: The database context.
    /// - Returns: The number of applied changes.
    /// - Throws: ``TradeRepublicFailure`` when no single depot can be chosen, or a save error.
    @discardableResult
    public static func apply(snapshot: TradeRepublicSnapshot, context: ModelContext) async throws -> Int {
        if snapshot.positions.isEmpty && snapshot.activities.isEmpty { return 0 }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let (checking, portfolio) = try targetAccounts(snapshot, accounts: accounts, context: context)
        replacePreviousImport(checking: checking, portfolio: portfolio, context: context)
        let stored = try context.fetch(FetchDescriptor<PortfolioHolding>()).filter { $0.accountID == portfolio.id }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var known = Set(entries.compactMap(\.importFingerprint))
        purgeFalseBuys(holdings: stored, positions: snapshot.positions, activities: snapshot.activities, checking: checking, portfolio: portfolio, known: &known, context: context)
        let periodStart = BankImportApplier.firstMainAccountPeriod(entries: entries, accounts: accounts, context: context)?.start
        let moves = TradeRepublicSync.changes(
            positions: snapshot.positions,
            holdings: heldPositions(stored),
            activities: snapshot.activities,
            known: known
        )
        replaceLumpBuys(holdings: stored, positions: snapshot.positions, activities: snapshot.activities, checking: checking, portfolio: portfolio, known: &known, context: context)
        repairMergedBuys(holdings: stored, activities: snapshot.activities, known: &known, context: context)
        let run = DepotRun(snapshot: snapshot, checking: checking, portfolio: portfolio, stored: stored, periodStart: periodStart, context: context)
        var dropping = Set(moves.compactMap { move -> String? in
            if case .drop(let isin) = move { return isin }
            return nil
        })
        var count = 0
        for move in moves {
            if try applyMove(move, run: run, known: &known, dropping: &dropping) { count += 1 }
        }
        try context.save()
        // Saveback arrives sized like a buy; it becomes cashback before the cash is reconciled.
        SavebackRepair.run(context: context)
        let fresh = try context.fetch(FetchDescriptor<PortfolioHolding>()).filter { $0.accountID == portfolio.id }
        relabelUnboughtOpenings(holdings: fresh, positions: snapshot.positions, activities: snapshot.activities, portfolio: portfolio, known: &known, context: context)
        scaleWholeLotsToLive(holdings: fresh, positions: snapshot.positions, activities: snapshot.activities, context: context)
        adoptSavingsPlans(from: snapshot.activities, plans: snapshot.plans, checking: checking, portfolio: portfolio, holdings: fresh, context: context)
        await MarketDataService.refresh(holdings: fresh, context: context)
        BankImportApplier.relinkOwnAccounts(context: context)
        reconcileChecking(checking, liveCents: snapshot.cashCents, context: context)
        return count
    }

    /// What every change of one session needs.
    private struct DepotRun {
        let snapshot: TradeRepublicSnapshot
        let checking: Account
        let portfolio: Account
        let stored: [PortfolioHolding]
        let periodStart: Date?
        let context: ModelContext
    }

    /// Finds or creates the Trade Republic checking account and its depot.
    private static func targetAccounts(
        _ snapshot: TradeRepublicSnapshot,
        accounts: [Account],
        context: ModelContext
    ) throws -> (checking: Account, portfolio: Account) {
        let named = accounts.map { NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain) }
        var tradeRepublic = accounts.first {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }
        let linked = tradeRepublic.flatMap { PortfolioLinkStore.portfolioID(for: $0.id) }
        let choice = TradeRepublicDepotTarget.choose(accounts: named, linkedPortfolioID: linked)
        if case .ambiguous = choice, !snapshot.positions.isEmpty { throw TradeRepublicFailure.noSingleDepot }
        let portfolio = try portfolio(choice, tradeRepublic: &tradeRepublic, context: context)
        if tradeRepublic == nil {
            tradeRepublic = makeChecking(context: context)
            PortfolioLinkStore.link(portfolio: portfolio.id, to: tradeRepublic!.id)
        }
        guard let checking = tradeRepublic else { throw TradeRepublicFailure.unreadable }
        return (checking, portfolio)
    }

    /// Describes the stored holdings for the comparison with the live depot.
    private static func heldPositions(_ stored: [PortfolioHolding]) -> [HeldPosition] {
        stored.map { holding in
            let lots = HoldingLotStore.lots(for: holding.id)
            return HeldPosition(
                symbol: holding.symbol,
                name: holding.name,
                quantity: lots.isEmpty ? holding.quantity : shareCount(lots),
                purchasePriceCents: holding.purchasePriceCents,
                latestLotDate: lots.map(\.date).max()
            )
        }
    }

    /// Applies one change.
    ///
    /// - Parameters:
    ///   - move: The change.
    ///   - run: The session's shared values.
    ///   - known: The fingerprints already booked.
    ///   - dropping: The ISINs that this session removes.
    /// - Returns: `true` when the change was applied.
    private static func applyMove(
        _ move: TradeRepublicMove,
        run: DepotRun,
        known: inout Set<String>,
        dropping: inout Set<String>
    ) throws -> Bool {
        switch move {
        case .cash(let id, let date, let title, let amountCents, let statementType):
            guard !isBeforePeriod(date, start: run.periodStart) else { return false }
            return insertCash(
                id: id,
                date: date,
                title: title,
                amountCents: amountCents,
                statementType: statementType,
                eventType: eventType(id: id, activities: run.snapshot.activities),
                checking: run.checking,
                portfolio: run.portfolio,
                known: known,
                context: run.context
            )
        case .grant(let id, let date, let title, let isin, let name, let quantity, let amountCents, let statementType):
            let holding = try openedHolding(isin: isin, name: name, run: run)
            guard insertGrant(
                id: id,
                date: date,
                title: title,
                quantity: quantity,
                amountCents: amountCents,
                statementType: statementType,
                eventType: eventType(id: id, isin: isin, activities: run.snapshot.activities),
                holding: holding,
                portfolio: run.portfolio,
                known: &known,
                context: run.context
            ) else { return false }
            syncUnlessDropping(holding, isin: isin, dropping: dropping, context: run.context)
            return true
        case .shares(_, let date, let isin, let name, let quantity, let unitCents):
            let holding = try openedHolding(isin: isin, name: name, run: run)
            guard insertShares(date: date, quantity: quantity, unitCents: unitCents, holding: holding) else { return false }
            syncUnlessDropping(holding, isin: isin, dropping: dropping, context: run.context)
            return true
        case .buy(let id, let date, let title, let isin, let name, let quantity, let amountCents, let savingsPlan):
            let trade = SessionTrade(id: id, date: date, title: title, isin: isin, name: name, quantity: quantity, amountCents: amountCents, sale: false, savingsPlan: savingsPlan)
            return try applyTrade(trade, run: run, known: &known, dropping: dropping)
        case .sale(let id, let date, let title, let isin, let name, let quantity, let amountCents):
            let trade = SessionTrade(id: id, date: date, title: title, isin: isin, name: name, quantity: quantity, amountCents: amountCents, sale: true, savingsPlan: false)
            return try applyTrade(trade, run: run, known: &known, dropping: dropping)
        case .drop(let isin):
            guard let holding = run.stored.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame })
                ?? holding(isin: isin, portfolio: run.portfolio, context: run.context) else { return false }
            HoldingMaintenance.retire(holding, context: run.context)
            dropping.remove(isin)
            return true
        }
    }

    /// A buy or sale from the session.
    private struct SessionTrade {
        let id: String
        let date: Date
        let title: String
        let isin: String
        let name: String
        let quantity: Double
        let amountCents: Int
        let sale: Bool
        let savingsPlan: Bool
    }

    /// Books a buy or sale on its holding.
    private static func applyTrade(
        _ trade: SessionTrade,
        run: DepotRun,
        known: inout Set<String>,
        dropping: Set<String>
    ) throws -> Bool {
        let holding = try openedHolding(isin: trade.isin, name: trade.name, run: run)
        guard insertTrade(
            id: trade.id,
            date: trade.date,
            title: trade.title,
            quantity: trade.quantity,
            amountCents: trade.amountCents,
            sale: trade.sale,
            savingsPlan: trade.savingsPlan,
            eventType: eventType(id: trade.id, isin: trade.isin, activities: run.snapshot.activities),
            holding: holding,
            checking: run.checking,
            portfolio: run.portfolio,
            known: &known,
            context: run.context,
            bookCash: !isBeforePeriod(trade.date, start: run.periodStart)
        ) else { return false }
        syncUnlessDropping(holding, isin: trade.isin, dropping: dropping, context: run.context)
        return true
    }

    /// Finds or creates a holding and records shares it held before this session.
    private static func openedHolding(isin: String, name: String, run: DepotRun) throws -> PortfolioHolding {
        let holding = try ensureHolding(isin: isin, name: name, portfolio: run.portfolio, stored: run.stored, context: run.context)
        openExistingSharesIfNeeded(holding)
        return holding
    }

    /// Rebuilds a holding from its lots, unless this session removes it anyway.
    private static func syncUnlessDropping(_ holding: PortfolioHolding, isin: String, dropping: Set<String>, context: ModelContext) {
        if !dropping.contains(isin) { _ = HoldingMaintenance.sync(holding, context: context) }
    }

    /// Says whether a date lies before the first period.
    private static func isBeforePeriod(_ date: Date, start: Date?) -> Bool {
        guard let start else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: start)
    }

    /// Finds or creates the depot chosen for the import.
    private static func portfolio(
        _ choice: DepotChoice,
        tradeRepublic: inout Account?,
        context: ModelContext
    ) throws -> Account {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        switch choice {
        case .ambiguous:
            throw TradeRepublicFailure.noSingleDepot
        case .existing(let id):
            guard let found = accounts.first(where: { $0.id == id }) else { throw TradeRepublicFailure.noSingleDepot }
            if PortfolioLinkStore.checkingID(for: found.id) == nil, let tradeRepublic {
                PortfolioLinkStore.link(portfolio: found.id, to: tradeRepublic.id)
            }
            return found
        case .create:
            let checking = tradeRepublic ?? makeChecking(context: context)
            tradeRepublic = checking
            let created = Account(name: L("Depot", "Portfolio"), kind: .portfolio, isLiquid: false)
            context.insert(created)
            PortfolioLinkStore.link(portfolio: created.id, to: checking.id)
            return created
        }
    }

    /// Finds or creates a holding.
    private static func ensureHolding(
        isin: String,
        name: String,
        portfolio: Account,
        stored: [PortfolioHolding],
        context: ModelContext
    ) throws -> PortfolioHolding {
        if let found = stored.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame })
            ?? holding(isin: isin, portfolio: portfolio, context: context) {
            if found.name.isEmpty { found.name = name }
            return found
        }
        let created = PortfolioHolding(
            accountID: portfolio.id,
            name: name.isEmpty ? isin : name,
            symbol: isin,
            quantity: 0,
            purchasePriceCents: 0,
            currentPriceCents: 0
        )
        context.insert(created)
        return created
    }

    /// Finds a holding by ISIN in the depot.
    private static func holding(isin: String, portfolio: Account, context: ModelContext) -> PortfolioHolding? {
        let stored = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        return stored.first { $0.accountID == portfolio.id && $0.symbol.caseInsensitiveCompare(isin) == .orderedSame }
    }

    /// A holding that was stored as a quantity, without lots, needs that quantity as a lot
    /// before a later purchase is added. Otherwise the new lot would replace the old shares.
    private static func openExistingSharesIfNeeded(_ holding: PortfolioHolding) {
        let lots = HoldingLotStore.lots(for: holding.id)
        guard lots.isEmpty, holding.quantity > 0.0000005 else { return }
        let date = HoldingPurchaseDateStore.date(for: holding.id) ?? holding.updatedAt
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: holding.quantity,
                unitPriceCents: max(holding.purchasePriceCents, 0),
                amountCents: -Int((holding.quantity * Double(max(holding.purchasePriceCents, 0))).rounded()),
                isSale: false,
                isSavingsPlan: false
            ),
            holdingID: holding.id
        )
    }

    /// A later sign-in rebuilds Trade Republic from the session. Own-account transfers without a session fingerprint stay.
    public static func shouldReplace(_ entry: LedgerEntry, checkingID: UUID, portfolioID: UUID) -> Bool {
        if entry.importFingerprint == TradeRepublicTimeline.openingBalanceFingerprint { return false }
        if isSessionFingerprint(entry.importFingerprint) { return true }
        if entry.kind == .transfer {
            return entry.fromAccountID == portfolioID || entry.toAccountID == portfolioID
        }
        if entry.accountID == portfolioID { return true }
        if entry.accountID == checkingID, entry.importFingerprint != nil { return true }
        return false
    }

    /// Says whether a fingerprint comes from a live session.
    public static func isSessionFingerprint(_ fingerprint: String?) -> Bool {
        guard let fingerprint, fingerprint.hasPrefix("tr-") else { return false }
        return fingerprint != TradeRepublicTimeline.openingBalanceFingerprint
    }

    /// Removes the bookings of the previous live import.
    private static func replacePreviousImport(checking: Account, portfolio: Account, context: ModelContext) {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let doomed = entries.filter { shouldReplace($0, checkingID: checking.id, portfolioID: portfolio.id) }
        let doomedIDs = Set(doomed.map(\.id))
        if let splits = try? context.fetch(FetchDescriptor<TransactionSplit>()) {
            for split in splits where doomedIDs.contains(split.transactionID) {
                context.delete(split)
            }
        }
        doomed.forEach(context.delete)
        let holdings = ((try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? [])
            .filter { $0.accountID == portfolio.id }
        for holding in holdings {
            ClosedPositionStore.remove(isin: holding.symbol)
            HoldingLotStore.removeAll(for: holding.id)
            HoldingPurchaseDateStore.remove(for: holding.id)
            MarketSymbolStore.remove(for: holding.id)
            PreviousCloseStore.remove(for: holding.id)
            context.delete(holding)
        }
        SavingsPlanStore.removeAll(portfolioID: portfolio.id)
    }

    /// Books one cash movement.
    private static func insertCash(
        id: String,
        date: Date,
        title: String,
        amountCents: Int,
        statementType: String,
        eventType: String = "",
        checking: Account,
        portfolio: Account,
        known: Set<String>,
        context: ModelContext
    ) -> Bool {
        if statementType == "IPO" {
            return insertIPO(
                id: id,
                date: date,
                title: title,
                amountCents: amountCents,
                eventType: eventType,
                checking: checking,
                portfolio: portfolio,
                known: known,
                context: context
            )
        }
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint), amountCents != 0 else { return false }
        if cashAlreadyBooked(date: date, amountCents: amountCents, checking: checking, context: context) {
            return false
        }
        let notes = extractNotes(statementType: statementType, symbol: nil, quantity: nil, unitCents: nil, eventType: eventType)
        let income = statementType == "Ertrag" || statementType == "Zinsen"
        let booked = income ? abs(amountCents) : amountCents
        context.insert(LedgerEntry(
            date: date,
            title: title,
            notes: notes,
            amountCents: booked,
            kind: booked < 0 ? .expense : .income,
            accountID: checking.id,
            importFingerprint: fingerprint
        ))
        return true
    }

    /// Cash reserved for an IPO is a Depotkauf on the checking account. Shares wait until the IPO is allocated.
    private static func insertIPO(
        id: String,
        date: Date,
        title: String,
        amountCents: Int,
        eventType: String,
        checking: Account,
        portfolio _: Account,
        known: Set<String>,
        context: ModelContext
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint), amountCents != 0 else { return false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty ? "IPO" : name
        let action = L("Depotkauf", "Portfolio buy")
        context.insert(LedgerEntry(
            date: date,
            title: "\(action): \(label)",
            notes: extractNotes(statementType: "IPO", symbol: nil, quantity: nil, unitCents: nil, eventType: eventType),
            amountCents: amountCents,
            kind: amountCents < 0 ? .expense : .income,
            accountID: checking.id,
            importFingerprint: fingerprint
        ))
        return true
    }

    /// The same cash movement may already exist from the bank import or as a transfer.
    private static func cashAlreadyBooked(
        date: Date,
        amountCents: Int,
        checking: Account,
        context: ModelContext
    ) -> Bool {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let absAmount = abs(amountCents)
        let checkingIDs = Set(
            ((try? context.fetch(FetchDescriptor<Account>())) ?? [])
                .filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
                .map(\.id)
        )
        return entries.contains { entry in
            guard abs(entry.amountCents) == absAmount else { return false }
            if entry.kind == .income || entry.kind == .expense {
                guard Calendar.current.isDate(entry.date, inSameDayAs: date) else { return false }
                guard entry.accountID == checking.id else { return false }
                // Two real card payments can share a day and an amount. Session rows stay distinct.
                return !TradeRepublicTimeline.isSessionFingerprint(entry.importFingerprint)
            }
            guard entry.kind == .transfer else { return false }
            guard withinDays(entry.date, of: date, days: BankImportApplier.ownAccountWindowDays) else { return false }
            let ends = [entry.fromAccountID, entry.toAccountID].compactMap { $0 }
            return ends.contains(checking.id) && ends.contains(where: { checkingIDs.contains($0) && $0 != checking.id })
        }
    }

    /// Books one trade with its lot.
    private static func insertTrade(
        id: String,
        date: Date,
        title: String,
        quantity: Double,
        amountCents: Int,
        sale: Bool,
        savingsPlan: Bool,
        eventType: String = "",
        holding: PortfolioHolding,
        checking: Account,
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext,
        bookCash: Bool = true
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard quantity > 0.0000005 else { return false }
        if !bookCash {
            let sameDay = HoldingLotStore.lots(for: holding.id).contains {
                !$0.isSale && abs($0.quantity - quantity) < 0.000001 && Calendar.current.isDate($0.date, inSameDayAs: date)
            }
            guard !sameDay else { return false }
        } else {
            guard !known.contains(fingerprint) else { return false }
        }
        let cash = abs(amountCents)
        let label = holding.name.isEmpty ? title : holding.name
        let action = sale ? L("Verkauf", "Sale") : (savingsPlan ? L("Sparplan", "Savings plan") : L("Kauf", "Purchase"))
        let unit = quantity > 0 ? Int((Double(cash) / quantity).rounded()) : 0
        var entryID: UUID?
        if bookCash, cash > 0 {
            if !sale, let reserved = adoptIPOReservation(
                cash: cash,
                holding: holding,
                checking: checking,
                portfolio: portfolio,
                context: context
            ) {
                reserved.date = date
                reserved.title = "\(action): \(label)"
                reserved.kind = .transfer
                reserved.amountCents = cash
                reserved.accountID = nil
                reserved.fromAccountID = checking.id
                reserved.toAccountID = portfolio.id
                reserved.notes = extractNotes(
                    statementType: "Handel",
                    symbol: holding.symbol,
                    quantity: quantity,
                    unitCents: unit,
                    eventType: eventType
                )
                reserved.importFingerprint = fingerprint
                entryID = reserved.id
            } else {
                let entry = LedgerEntry(
                    date: date,
                    title: "\(action): \(label)",
                    notes: extractNotes(statementType: "Handel", symbol: holding.symbol, quantity: quantity, unitCents: unit, eventType: eventType),
                    amountCents: cash,
                    kind: .transfer,
                    fromAccountID: sale ? portfolio.id : checking.id,
                    toAccountID: sale ? checking.id : portfolio.id,
                    importFingerprint: fingerprint
                )
                context.insert(entry)
                entryID = entry.id
            }
        }
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: quantity,
                unitPriceCents: unit,
                amountCents: sale ? cash : -cash,
                isSale: sale,
                isSavingsPlan: savingsPlan && !sale,
                ledgerEntryID: entryID
            ),
            holdingID: holding.id
        )
        if bookCash { known.insert(fingerprint) }
        if !sale, HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(date, for: holding.id)
        }
        return true
    }

    /// Cashback and gifts add the shares and an income booking. The checking account is not charged.
    private static func insertGrant(
        id: String,
        date: Date,
        title: String,
        quantity: Double,
        amountCents: Int,
        statementType: String,
        eventType: String = "",
        holding: PortfolioHolding,
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint) else { return false }
        let label = holding.name.isEmpty ? title : holding.name
        let gift = statementType != "Cashback"
        let action = gift ? L("Depotgeschenk", "Portfolio gift") : "Cashback"
        let shown = abs(amountCents)
        if shown > 0 || gift {
            context.insert(LedgerEntry(
                date: date,
                title: "\(action): \(label)",
                notes: extractNotes(
                    statementType: statementType,
                    symbol: holding.symbol,
                    quantity: quantity > 0.0000005 ? quantity : nil,
                    unitCents: nil,
                    eventType: eventType
                ),
                amountCents: shown,
                kind: .income,
                accountID: portfolio.id,
                importFingerprint: fingerprint
            ))
        }
        if quantity > 0.0000005 {
            HoldingLotStore.add(
                HoldingLot(
                    date: date,
                    quantity: quantity,
                    unitPriceCents: gift ? 0 : (shown > 0 ? Int((Double(shown) / quantity).rounded()) : 0),
                    amountCents: gift ? 0 : shown,
                    isSale: false,
                    isSavingsPlan: false,
                    source: gift ? "gift" : "cashback"
                ),
                holdingID: holding.id
            )
        }
        known.insert(fingerprint)
        if HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(date, for: holding.id)
        }
        return shown > 0 || quantity > 0.0000005 || gift
    }

    /// Turns a reserved IPO amount into the real purchase.
    private static func adoptIPOReservation(
        cash: Int,
        holding: PortfolioHolding,
        checking: Account,
        portfolio: Account,
        context: ModelContext
    ) -> LedgerEntry? {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let label = holding.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { entry in
            guard abs(abs(entry.amountCents) - cash) <= 150 else { return false }
            let onChecking = (entry.kind == .expense || entry.kind == .income) && entry.accountID == checking.id
            let asTransfer = entry.kind == .transfer
                && entry.fromAccountID == checking.id
                && entry.toAccountID == portfolio.id
            guard onChecking || asTransfer else { return false }
            let notes = entry.notes.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            let titled = entry.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            guard notes.contains("typ: ipo")
                || titled.hasPrefix("ipo:")
                || titled.hasPrefix("depotkauf:")
                || titled.contains("depotkauf")
                || titled.contains("portfolio buy")
            else { return false }
            if !symbol.isEmpty, notes.localizedCaseInsensitiveContains(symbol) { return true }
            if !label.isEmpty, entry.title.localizedStandardContains(label) { return true }
            return abs(entry.amountCents) == cash
        }
    }

    /// Shares the timeline does not explain. They stay in the depot and do not leave the cash account.
    private static func insertShares(
        date: Date,
        quantity: Double,
        unitCents: Int,
        holding: PortfolioHolding
    ) -> Bool {
        guard quantity > 0.0000005 else { return false }
        let lots = HoldingLotStore.lots(for: holding.id)
        if lots.contains(where: { !$0.isSale && $0.ledgerEntryID == nil && abs($0.quantity - quantity) < 0.000001 }) {
            return false
        }
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: quantity,
                unitPriceCents: unitCents,
                amountCents: 0,
                isSale: false,
                isSavingsPlan: false,
                source: "opening"
            ),
            holdingID: holding.id
        )
        if HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(date, for: holding.id)
        }
        return true
    }

    /// PDF notes: Typ, ISIN, Stück, Kurs, plus the Trade Republic event type.
    private static func extractNotes(
        statementType: String,
        symbol: String?,
        quantity: Double?,
        unitCents: Int?,
        eventType: String
    ) -> String {
        var lines: [String] = []
        if !statementType.isEmpty {
            lines.append("\(L("Typ", "Type")): \(statementType)")
        }
        if let symbol, !symbol.isEmpty {
            lines.append("ISIN: \(symbol)")
        }
        if let quantity, quantity > 0.0000005 {
            lines.append("\(L("Stück", "Quantity")): \(quantityText(quantity))")
        }
        if let unitCents, unitCents > 0 {
            lines.append("\(L("Kurs", "Price")): \(Money.string(cents: unitCents))")
        }
        if !eventType.isEmpty {
            lines.append("\(L("Ereignis", "Event")): \(eventType)")
        }
        return lines.joined(separator: "\n")
    }

    /// Returns the event type of an activity.
    private static func eventType(id: String, isin: String = "", activities: [TradeRepublicActivity]) -> String {
        if let item = activities.first(where: { $0.id == id }) { return item.eventType }
        if id.hasPrefix("gift-") {
            let name = activities.first { $0.isin.caseInsensitiveCompare(isin) == .orderedSame }?.title ?? ""
            return activities.first {
                TradeRepublicSync.matchesInstrument($0, isin: isin, name: name) && $0.isGrant
            }?.eventType ?? ""
        }
        if id.hasPrefix("delta-") {
            return activities.first {
                $0.trade && $0.amountCents > 0 && $0.isin.caseInsensitiveCompare(isin) == .orderedSame
            }?.eventType ?? ""
        }
        return ""
    }

    /// Says whether two dates lie within a number of days.
    private static func withinDays(_ date: Date, of other: Date, days: Int) -> Bool {
        let calendar = Calendar.current
        let delta = abs(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: other)
        ).day ?? 0)
        return delta <= days
    }

    /// Formats a share count without trailing zeros.
    private static func quantityText(_ quantity: Double) -> String {
        var text = String(format: "%.6f", quantity)
        while text.contains("."), text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    /// Share lots that were dividends or interest are removed before the quantity is compared.
    /// A collapsed lot stays only when the timeline has no real purchase. Older buys outside the timeline stay.
    private static func purgeFalseBuys(
        holdings: [PortfolioHolding],
        positions: [TradeRepublicPosition],
        activities: [TradeRepublicActivity],
        checking: Account,
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext
    ) {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let byID = Dictionary(activities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for holding in holdings {
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbol.isEmpty else { continue }
            guard let position = positions.first(where: { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }) else { continue }
            let average = position.averageBuyInCents ?? 0
            let accepted = activities.filter {
                $0.isin.caseInsensitiveCompare(symbol) == .orderedSame && TradeRepublicSync.purchase($0, averageCents: average)
            }
            let acceptedIDs = Set(accepted.map(\.id))
            var removedCollapsed = false
            for lot in HoldingLotStore.lots(for: holding.id) where !lot.isSale {
                guard let entryID = lot.ledgerEntryID,
                      let entry = entries.first(where: { $0.id == entryID }),
                      let fingerprint = entry.importFingerprint,
                      fingerprint.hasPrefix("tr-") else { continue }
                let eventID = String(fingerprint.dropFirst(3))
                if eventID.hasPrefix("open-") {
                    let grants = activities.filter {
                        $0.isGrant && TradeRepublicSync.matchesInstrument($0, isin: symbol, name: holding.name)
                    }
                    let sizedGrant = grants.contains { ($0.quantity ?? 0) > 0.0000005 }
                    known.remove(fingerprint)
                    context.delete(entry)
                    if acceptedIDs.isEmpty && !sizedGrant {
                        if let grant = grants.min(by: { $0.date < $1.date }) {
                            let shown = abs(lot.amountCents)
                            keepReceipt(
                                lot: lot,
                                holding: holding,
                                date: grant.date,
                                source: grant.statementType == "Cashback" ? "cashback" : "gift"
                            )
                            if grant.amountCents == 0, shown > 0 {
                                _ = insertGrant(
                                    id: grant.id,
                                    date: grant.date,
                                    title: grant.title.isEmpty ? holding.name : grant.title,
                                    quantity: 0,
                                    amountCents: shown,
                                    statementType: grant.statementType,
                                    holding: holding,
                                    portfolio: portfolio,
                                    known: &known,
                                    context: context
                                )
                            }
                        } else {
                            keepSharesWithoutCash(lot: lot, holding: holding, activities: activities)
                        }
                        continue
                    }
                    removedCollapsed = true
                    HoldingLotStore.remove(lotID: lot.id, holdingID: holding.id)
                    continue
                } else if let item = byID[eventID] {
                    if TradeRepublicSync.purchase(item, averageCents: average) { continue }
                    if item.isGrant, (item.quantity ?? 0) < 0.0000005 {
                        known.remove(fingerprint)
                        context.delete(entry)
                        keepReceipt(
                            lot: lot,
                            holding: holding,
                            date: item.date,
                            source: item.statementType == "Cashback" ? "cashback" : "gift"
                        )
                        continue
                    }
                } else {
                    continue
                }
                known.remove(fingerprint)
                context.delete(entry)
                HoldingLotStore.remove(lotID: lot.id, holdingID: holding.id)
            }
            guard removedCollapsed else {
                _ = HoldingMaintenance.sync(holding, context: context)
                continue
            }
            for event in accepted.sorted(by: { $0.date < $1.date }) {
                _ = insertTrade(
                    id: event.id,
                    date: event.date,
                    title: event.title,
                    quantity: event.quantity ?? 0,
                    amountCents: event.amountCents,
                    sale: false,
                    savingsPlan: event.savingsPlan,
                    holding: holding,
                    checking: checking,
                    portfolio: portfolio,
                    known: &known,
                    context: context
                )
            }
            let covered = shareCount(HoldingLotStore.lots(for: holding.id))
            let rest = position.quantity - covered
            if rest > 0.001, average > 0 {
                let oldest = accepted.map(\.date).min()
                    ?? HoldingLotStore.lots(for: holding.id).map(\.date).min()
                    ?? FinanceClock.now
                let date = Calendar.current.date(byAdding: .day, value: -1, to: oldest) ?? oldest
                _ = insertShares(date: date, quantity: rest, unitCents: average, holding: holding)
            }
            _ = HoldingMaintenance.sync(holding, context: context)
        }
    }

    /// The collapsed booking charged the cash account on the import day. The shares stay, without that charge.
    private static func keepSharesWithoutCash(
        lot: HoldingLot,
        holding: PortfolioHolding,
        activities: [TradeRepublicActivity]
    ) {
        var lots = HoldingLotStore.lots(for: holding.id)
        guard let index = lots.firstIndex(where: { $0.id == lot.id }) else { return }
        if let oldest = activities.map(\.date).min() {
            lots[index].date = Calendar.current.date(byAdding: .day, value: -1, to: oldest) ?? oldest
        }
        lots[index].amountCents = 0
        lots[index].ledgerEntryID = nil
        lots[index].source = "opening"
        HoldingLotStore.replace(lots, holdingID: holding.id)
    }

    /// A position with no purchase in the timeline was received, not bought. Label it as a gift.
    private static func relabelUnboughtOpenings(
        holdings: [PortfolioHolding],
        positions: [TradeRepublicPosition],
        activities: [TradeRepublicActivity],
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext
    ) {
        let dates = TradeRepublicSync.giftDates(positions: positions, activities: activities)
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for holding in holdings {
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbol.isEmpty else { continue }
            guard let position = positions.first(where: { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }) else {
                continue
            }
            let bought = activities.contains {
                $0.isin.caseInsensitiveCompare(symbol) == .orderedSame
                    && TradeRepublicSync.purchase($0, averageCents: position.averageBuyInCents ?? 0)
            }
            guard !bought else { continue }
            var lots = HoldingLotStore.lots(for: holding.id)
            let grant = activities.filter {
                $0.isGrant && TradeRepublicSync.matchesInstrument($0, isin: symbol, name: holding.name)
            }.min(by: { $0.date < $1.date })
            let giftDate = grant?.date ?? dates[symbol]
            var changed = false
            for index in lots.indices where !lots[index].isSale {
                let unlabeled = lots[index].source == "opening" || lots[index].source.isEmpty
                guard unlabeled else { continue }
                if let ledger = lots[index].ledgerEntryID,
                   let entry = entries.first(where: { $0.id == ledger }) {
                    if let fingerprint = entry.importFingerprint { known.remove(fingerprint) }
                    context.delete(entry)
                }
                lots[index].ledgerEntryID = nil
                lots[index].amountCents = 0
                lots[index].unitPriceCents = 0
                lots[index].source = "gift"
                if let giftDate { lots[index].date = giftDate }
                changed = true
            }
            if changed {
                HoldingLotStore.replace(lots, holdingID: holding.id)
            }
            guard changed else { continue }
            _ = insertGrant(
                id: "gift-\(symbol)",
                date: giftDate ?? lots.map(\.date).min() ?? FinanceClock.now,
                title: holding.name,
                quantity: 0,
                amountCents: Int((holding.quantity * Double(position.averageBuyInCents ?? 0)).rounded()),
                statementType: "Depotgeschenk",
                eventType: grant?.eventType ?? "",
                holding: holding,
                portfolio: portfolio,
                known: &known,
                context: context
            )
            _ = HoldingMaintenance.sync(holding, context: context)
        }
    }

    /// The shares arrived as cashback or a gift. The date stays the event date, and the cash account is not charged.
    private static func keepReceipt(
        lot: HoldingLot,
        holding: PortfolioHolding,
        date: Date,
        source: String
    ) {
        var lots = HoldingLotStore.lots(for: holding.id)
        guard let index = lots.firstIndex(where: { $0.id == lot.id }) else { return }
        lots[index].date = date
        lots[index].amountCents = 0
        lots[index].unitPriceCents = 0
        lots[index].ledgerEntryID = nil
        lots[index].source = source
        HoldingLotStore.replace(lots, holdingID: holding.id)
    }

    /// One lot for the whole position, dated whenever the import ran, is replaced by the real purchases.
    private static func replaceLumpBuys(
        holdings: [PortfolioHolding],
        positions: [TradeRepublicPosition],
        activities: [TradeRepublicActivity],
        checking: Account,
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext
    ) {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for holding in holdings {
            let symbol = holding.symbol.uppercased()
            let position = positions.first { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }
            let events = activities.filter {
                TradeRepublicSync.purchase($0, averageCents: position?.averageBuyInCents ?? 0)
                    && $0.isin.caseInsensitiveCompare(symbol) == .orderedSame
            }.sorted { $0.date < $1.date }
            guard !events.isEmpty else { continue }
            let lots = HoldingLotStore.lots(for: holding.id).filter { !$0.isSale }
            guard lots.count == 1, let lump = lots.first else { continue }
            let live = position?.quantity ?? lump.quantity
            let smaller = events.contains { ($0.quantity ?? 0) + 0.0000005 < lump.quantity }
            guard smaller, abs(lump.quantity - live) < max(0.05, live * 0.02) else { continue }
            if let entryID = lump.ledgerEntryID, let entry = entries.first(where: { $0.id == entryID }) {
                if let fingerprint = entry.importFingerprint { known.remove(fingerprint) }
                context.delete(entry)
            }
            HoldingLotStore.remove(lotID: lump.id, holdingID: holding.id)
            for event in events {
                known.remove(TradeRepublicTimeline.fingerprint(event.id))
                _ = insertTrade(
                    id: event.id,
                    date: event.date,
                    title: event.title,
                    quantity: event.quantity ?? 0,
                    amountCents: event.amountCents,
                    sale: false,
                    savingsPlan: event.savingsPlan,
                    holding: holding,
                    checking: checking,
                    portfolio: portfolio,
                    known: &known,
                    context: context
                )
            }
            let covered = events.reduce(0.0) { $0 + ($1.quantity ?? 0) }
            let rest = live - covered
            if rest > 0.001, let cost = position?.averageBuyInCents, cost > 0, let oldest = events.map(\.date).min() {
                let date = Calendar.current.date(byAdding: .day, value: -1, to: oldest) ?? oldest
                known.remove(TradeRepublicTimeline.fingerprint("open-\(symbol)"))
                _ = insertTrade(
                    id: "open-\(symbol)",
                    date: date,
                    title: holding.name,
                    quantity: rest,
                    amountCents: -Int((rest * Double(cost)).rounded()),
                    sale: false,
                    savingsPlan: false,
                    holding: holding,
                    checking: checking,
                    portfolio: portfolio,
                    known: &known,
                    context: context
                )
            }
            _ = HoldingMaintenance.sync(holding, context: context)
        }
    }

    /// A lot that received every new share at one event's cash is split back into those purchases.
    private static func repairMergedBuys(
        holdings: [PortfolioHolding],
        activities: [TradeRepublicActivity],
        known: inout Set<String>,
        context: ModelContext
    ) {
        let calendar = Calendar.current
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        for holding in holdings {
            let symbol = holding.symbol.uppercased()
            let events = activities.filter {
                TradeRepublicSync.purchase($0, averageCents: 0)
                    && $0.isin.caseInsensitiveCompare(symbol) == .orderedSame
            }.sorted { $0.date < $1.date }
            guard !events.isEmpty else { continue }
            var lots = HoldingLotStore.lots(for: holding.id)
            var used = Set<UUID>()
            for event in events {
                let cash = abs(event.amountCents)
                guard let index = lots.firstIndex(where: { lot in
                    !used.contains(lot.id) && !lot.isSale
                        && calendar.isDate(lot.date, inSameDayAs: event.date)
                        && abs(abs(lot.amountCents) - cash) <= 150
                }) else { continue }
                used.insert(lots[index].id)
                let quantity = event.quantity ?? lots[index].quantity
                lots[index].quantity = quantity
                lots[index].unitPriceCents = quantity > 0 ? Int((Double(cash) / quantity).rounded()) : lots[index].unitPriceCents
                lots[index].amountCents = -cash
                lots[index].isSavingsPlan = event.savingsPlan
                lots[index].date = event.date
                if let entryID = lots[index].ledgerEntryID, let entry = entries.first(where: { $0.id == entryID }) {
                    let label = holding.name.isEmpty ? event.title : holding.name
                    entry.title = "\(event.savingsPlan ? L("Sparplan", "Savings plan") : L("Kauf", "Purchase")): \(label)"
                    entry.date = event.date
                }
                known.insert(TradeRepublicTimeline.fingerprint(event.id))
            }
            HoldingLotStore.replace(lots, holdingID: holding.id)
        }
    }

    /// Creates savings plans from the live plans and past executions.
    private static func adoptSavingsPlans(
        from activities: [TradeRepublicActivity],
        plans livePlans: [TradeRepublicPlan],
        checking: Account,
        portfolio: Account,
        holdings: [PortfolioHolding],
        context: ModelContext
    ) {
        if !livePlans.isEmpty {
            let live = Set(livePlans.map { $0.isin.uppercased() })
            for existing in SavingsPlanStore.all() where existing.portfolioAccountID == portfolio.id && !live.contains(existing.isin.uppercased()) {
                SavingsPlanStore.remove(id: existing.id)
            }
            for plan in livePlans where plan.active {
                let executions = activities.filter {
                    $0.savingsPlan && $0.amountCents < 0 && $0.isin.caseInsensitiveCompare(plan.isin) == .orderedSame
                }
                let last = executions.map(\.date).max() ?? FinanceClock.now
                let holding = holdings.first { $0.symbol.caseInsensitiveCompare(plan.isin) == .orderedSame }
                let name = plan.name.isEmpty ? (holding?.name ?? plan.isin) : plan.name
                var record = SavingsPlanRecord(
                    id: UUID(),
                    isin: plan.isin.uppercased(),
                    name: name,
                    amountCents: plan.amountCents,
                    cadenceRaw: TradeRepublicPlans.cadence(for: plan.interval).rawValue,
                    checkingAccountID: checking.id,
                    portfolioAccountID: portfolio.id,
                    holdingID: holding?.id,
                    lastExecution: last,
                    historyThrough: last,
                    active: true
                )
                if let existing = SavingsPlanStore.all().first(where: {
                    $0.portfolioAccountID == portfolio.id && $0.isin.caseInsensitiveCompare(plan.isin) == .orderedSame
                }) {
                    record.id = existing.id
                    record.fixedCostID = existing.fixedCostID
                }
                SavingsPlanStore.upsert(record)
            }
            SavingsPlanFixedCosts.sync(context: context)
            return
        }
        let rows = activities.compactMap { item -> ImportedTransaction? in
            guard item.savingsPlan, let quantity = item.quantity, quantity > 0.0000005, item.amountCents < 0 else { return nil }
            return ImportedTransaction(
                date: item.date,
                title: "\(L("Sparplan", "Savings plan")): \(item.title)",
                notes: item.isin,
                amountCents: item.amountCents,
                iban: "",
                senderIBAN: "",
                recipientIBAN: "",
                fingerprint: TradeRepublicTimeline.fingerprint(item.id),
                trade: ImportedSecurityTrade(
                    isin: item.isin,
                    name: item.title.isEmpty ? item.isin : item.title,
                    quantity: quantity,
                    isSale: false,
                    isSavingsPlan: true
                )
            )
        }
        let built = SavingsPlanBuilder.build(
            rows: rows,
            checkingID: checking.id,
            portfolioID: portfolio.id,
            holdings: holdings
        )
        for plan in built {
            if var existing = SavingsPlanStore.all().first(where: {
                $0.portfolioAccountID == portfolio.id && $0.isin.caseInsensitiveCompare(plan.isin) == .orderedSame
            }) {
                existing.amountCents = plan.amountCents
                existing.cadenceRaw = plan.cadenceRaw
                existing.lastExecution = plan.lastExecution
                existing.historyThrough = plan.historyThrough
                existing.active = plan.active
                existing.name = plan.name
                existing.holdingID = plan.holdingID
                existing.checkingAccountID = checking.id
                SavingsPlanStore.upsert(existing)
            } else {
                SavingsPlanStore.upsert(plan)
            }
        }
        SavingsPlanFixedCosts.sync(context: context)
    }

    /// Lots that overshoot the live quantity, with no sale in the history, are scaled.
    private static func scaleWholeLotsToLive(
        holdings: [PortfolioHolding],
        positions: [TradeRepublicPosition],
        activities: [TradeRepublicActivity],
        context: ModelContext
    ) {
        for holding in holdings {
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let position = positions.first(where: { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }) else {
                continue
            }
            var lots = HoldingLotStore.lots(for: holding.id)
            let have = shareCount(lots)
            let live = position.quantity
            guard have > live + 0.001, live > 0.0000005 else { continue }
            let sold = lots.contains(where: { $0.isSale })
                || activities.contains {
                    $0.trade && $0.amountCents > 0 && $0.isin.caseInsensitiveCompare(symbol) == .orderedSame
                }
            guard !sold else { continue }
            let factor = live / have
            guard factor > 0.000001, factor < 0.999 else { continue }
            for index in lots.indices where !lots[index].isSale {
                lots[index].quantity *= factor
            }
            HoldingLotStore.replace(lots, holdingID: holding.id)
            _ = HoldingMaintenance.sync(holding, context: context)
        }
    }

    /// Counts the shares of the lots.
    private static func shareCount(_ lots: [HoldingLot]) -> Double {
        var held = 0.0
        for lot in lots.sorted(by: { $0.date < $1.date }) {
            held += lot.isSale ? -lot.quantity : lot.quantity
        }
        return max(0, held)
    }

    /// Creates the Trade Republic checking account.
    private static func makeChecking(context: ModelContext) -> Account {
        let account = Account(name: "Trade Republic", kind: .checking, isLiquid: true, isMain: false)
        context.insert(account)
        return account
    }

    /// The session cash amount is the current Trade Republic checking balance.
    private static func reconcileChecking(_ checking: Account, liveCents: Int?, context: ModelContext) {
        guard let liveCents else { return }
        var entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let hasOpening = entries.contains {
            $0.kind == .adjustment
                && $0.accountID == checking.id
                && !ImportBalance.isCurrentPin($0, accountID: checking.id)
        }
        if !hasOpening {
            let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
            let start = BankImportApplier.firstMainAccountPeriod(
                entries: entries,
                accounts: accounts,
                context: context
            )?.start ?? Calendar.current.startOfDay(for: FinanceClock.now)
            let startDay = Calendar.current.startOfDay(for: start)
            let later = entries.reduce(0) { partial, entry in
                guard Calendar.current.startOfDay(for: entry.date) > startDay else { return partial }
                return partial + checkingEffect(entry, account: checking)
            }
            let opening = LedgerEntry(
                date: startDay,
                title: L("Startsaldo", "Opening balance"),
                notes: "Typ: Startsaldo",
                amountCents: liveCents - later,
                kind: .adjustment,
                accountID: checking.id,
                importFingerprint: TradeRepublicTimeline.openingBalanceFingerprint
            )
            context.insert(opening)
            entries.append(opening)
        }
        _ = ImportBalance.correction(
            account: checking,
            entries: &entries,
            currentCents: liveCents,
            date: FinanceClock.now,
            context: context
        )
        try? context.save()
    }

    /// Returns a booking's effect on the checking balance.
    private static func checkingEffect(_ entry: LedgerEntry, account: Account) -> Int {
        switch entry.kind {
        case .income, .expense:
            return entry.accountID == account.id ? entry.amountCents : 0
        case .transfer:
            var value = 0
            if entry.fromAccountID == account.id { value -= abs(entry.amountCents) }
            if entry.toAccountID == account.id { value += abs(entry.amountCents) }
            return value
        case .adjustment:
            return 0
        }
    }
}

/// Asks for the balance before the first imported booking.
@MainActor
public enum TradeRepublicOpeningBalance {
    /// The cash balance is missing for the start of the main account's first period.
    public static func missingDate(context: ModelContext) -> Date? {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let checking = accounts.first(where: {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }) else { return nil }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        if entries.contains(where: { $0.kind == .adjustment && $0.accountID == checking.id }) { return nil }
        return BankImportApplier.firstMainAccountPeriod(entries: entries, accounts: accounts, context: context)?.start
    }

    /// Stores the entered opening balance.
    public static func store(_ cents: Int, context: ModelContext) {
        guard let date = missingDate(context: context) else { return }
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let checking = accounts.first(where: {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }) else { return }
        context.insert(LedgerEntry(
            date: Calendar.current.startOfDay(for: date),
            title: L("Startsaldo", "Opening balance"),
            notes: "Typ: Startsaldo",
            amountCents: cents,
            kind: .adjustment,
            accountID: checking.id,
            importFingerprint: "tr-startsaldo"
        ))
        try? context.save()
    }
}
