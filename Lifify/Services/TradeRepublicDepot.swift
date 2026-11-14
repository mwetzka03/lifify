import Foundation
import SwiftData

@MainActor
enum TradeRepublicDepotApplier {
    /// Brings the depot and the Trade Republic checking account in line with one session.
    /// A position the session omits is removed. A larger quantity becomes a new lot and a booking.
    @discardableResult
    static func apply(snapshot: TradeRepublicSnapshot, context: ModelContext) async throws -> Int {
        if snapshot.positions.isEmpty && snapshot.activities.isEmpty { return 0 }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let named = accounts.map {
            NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain)
        }
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
        let stored = try context.fetch(FetchDescriptor<PortfolioHolding>()).filter { $0.accountID == portfolio.id }
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let known = Set(entries.compactMap(\.importFingerprint))
        let held = stored.map { holding in
            let lots = HoldingLotStore.lots(for: holding.id)
            return HeldPosition(
                symbol: holding.symbol,
                name: holding.name,
                quantity: lots.isEmpty ? holding.quantity : shareCount(lots),
                purchasePriceCents: holding.purchasePriceCents,
                latestLotDate: lots.map(\.date).max()
            )
        }
        let moves = TradeRepublicSync.changes(
            positions: snapshot.positions,
            holdings: held,
            activities: snapshot.activities,
            known: known
        )
        var count = 0
        var dropping = Set(moves.compactMap { move -> String? in
            if case .drop(let isin) = move { return isin }
            return nil
        })
        for move in moves {
            switch move {
            case .cash(let id, let date, let title, let amountCents):
                guard insertCash(id: id, date: date, title: title, amountCents: amountCents, checking: checking, known: known, context: context) else { continue }
                count += 1
            case .buy(let id, let date, let title, let isin, let name, let quantity, let amountCents):
                let holding = try ensureHolding(isin: isin, name: name, portfolio: portfolio, stored: stored, context: context)
                openExistingSharesIfNeeded(holding)
                guard insertTrade(id: id, date: date, title: title, quantity: quantity, amountCents: amountCents, sale: false, holding: holding, checking: checking, portfolio: portfolio, known: known, context: context) else { continue }
                if !dropping.contains(isin) { _ = HoldingMaintenance.sync(holding, context: context) }
                count += 1
            case .sale(let id, let date, let title, let isin, let name, let quantity, let amountCents):
                guard let holding = stored.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame })
                    ?? holding(isin: isin, portfolio: portfolio, context: context) else { continue }
                if holding.name.isEmpty { holding.name = name }
                openExistingSharesIfNeeded(holding)
                guard insertTrade(id: id, date: date, title: title, quantity: quantity, amountCents: amountCents, sale: true, holding: holding, checking: checking, portfolio: portfolio, known: known, context: context) else { continue }
                if !dropping.contains(isin) { _ = HoldingMaintenance.sync(holding, context: context) }
                count += 1
            case .drop(let isin):
                guard let holding = stored.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame })
                    ?? holding(isin: isin, portfolio: portfolio, context: context) else { continue }
                HoldingMaintenance.retire(holding, context: context)
                dropping.remove(isin)
                count += 1
            }
        }
        try context.save()
        let fresh = try context.fetch(FetchDescriptor<PortfolioHolding>()).filter { $0.accountID == portfolio.id }
        await MarketDataService.refresh(holdings: fresh, context: context)
        return count
    }

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

    private static func insertCash(
        id: String,
        date: Date,
        title: String,
        amountCents: Int,
        checking: Account,
        known: Set<String>,
        context: ModelContext
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint), amountCents != 0 else { return false }
        context.insert(LedgerEntry(
            date: date,
            title: title,
            amountCents: amountCents,
            kind: amountCents < 0 ? .expense : .income,
            accountID: checking.id,
            importFingerprint: fingerprint
        ))
        return true
    }

    private static func insertTrade(
        id: String,
        date: Date,
        title: String,
        quantity: Double,
        amountCents: Int,
        sale: Bool,
        holding: PortfolioHolding,
        checking: Account,
        portfolio: Account,
        known: Set<String>,
        context: ModelContext
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint), quantity > 0.0000005 else { return false }
        let cash = abs(amountCents)
        let label = holding.name.isEmpty ? title : holding.name
        var entryID: UUID?
        if cash > 0 {
            let entry = LedgerEntry(
                date: date,
                title: "\(sale ? L("Verkauf", "Sale") : L("Kauf", "Purchase")): \(label)",
                notes: holding.symbol,
                amountCents: cash,
                kind: .transfer,
                fromAccountID: sale ? portfolio.id : checking.id,
                toAccountID: sale ? checking.id : portfolio.id,
                importFingerprint: fingerprint
            )
            context.insert(entry)
            entryID = entry.id
        }
        let unit = quantity > 0 ? Int((Double(cash) / quantity).rounded()) : 0
        HoldingLotStore.add(
            HoldingLot(
                date: date,
                quantity: quantity,
                unitPriceCents: unit,
                amountCents: sale ? cash : -cash,
                isSale: sale,
                isSavingsPlan: false,
                ledgerEntryID: entryID
            ),
            holdingID: holding.id
        )
        if !sale, HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(date, for: holding.id)
        }
        return true
    }

    private static func shareCount(_ lots: [HoldingLot]) -> Double {
        var held = 0.0
        for lot in lots.sorted(by: { $0.date < $1.date }) {
            held += lot.isSale ? -lot.quantity : lot.quantity
        }
        return max(0, held)
    }

    private static func makeChecking(context: ModelContext) -> Account {
        let account = Account(name: "Trade Republic", kind: .checking, isLiquid: true, isMain: false)
        context.insert(account)
        return account
    }
}
