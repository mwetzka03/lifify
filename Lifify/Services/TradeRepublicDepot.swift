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
        var known = Set(entries.compactMap(\.importFingerprint))
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
        replaceLumpBuys(holdings: stored, positions: snapshot.positions, activities: snapshot.activities, checking: checking, portfolio: portfolio, known: &known, context: context)
        repairMergedBuys(holdings: stored, activities: snapshot.activities, known: &known, context: context)
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
            case .buy(let id, let date, let title, let isin, let name, let quantity, let amountCents, let savingsPlan):
                let holding = try ensureHolding(isin: isin, name: name, portfolio: portfolio, stored: stored, context: context)
                openExistingSharesIfNeeded(holding)
                guard insertTrade(id: id, date: date, title: title, quantity: quantity, amountCents: amountCents, sale: false, savingsPlan: savingsPlan, holding: holding, checking: checking, portfolio: portfolio, known: &known, context: context) else { continue }
                if !dropping.contains(isin) { _ = HoldingMaintenance.sync(holding, context: context) }
                count += 1
            case .sale(let id, let date, let title, let isin, let name, let quantity, let amountCents):
                guard let holding = stored.first(where: { $0.symbol.caseInsensitiveCompare(isin) == .orderedSame })
                    ?? holding(isin: isin, portfolio: portfolio, context: context) else { continue }
                if holding.name.isEmpty { holding.name = name }
                openExistingSharesIfNeeded(holding)
                guard insertTrade(id: id, date: date, title: title, quantity: quantity, amountCents: amountCents, sale: true, savingsPlan: false, holding: holding, checking: checking, portfolio: portfolio, known: &known, context: context) else { continue }
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
        adoptSavingsPlans(from: snapshot.activities, plans: snapshot.plans, checking: checking, portfolio: portfolio, holdings: fresh, context: context)
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
        savingsPlan: Bool,
        holding: PortfolioHolding,
        checking: Account,
        portfolio: Account,
        known: inout Set<String>,
        context: ModelContext
    ) -> Bool {
        let fingerprint = TradeRepublicTimeline.fingerprint(id)
        guard !known.contains(fingerprint), quantity > 0.0000005 else { return false }
        let cash = abs(amountCents)
        let label = holding.name.isEmpty ? title : holding.name
        let action = sale ? L("Verkauf", "Sale") : (savingsPlan ? L("Sparplan", "Savings plan") : L("Kauf", "Purchase"))
        var entryID: UUID?
        if cash > 0 {
            let entry = LedgerEntry(
                date: date,
                title: "\(action): \(label)",
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
                isSavingsPlan: savingsPlan && !sale,
                ledgerEntryID: entryID
            ),
            holdingID: holding.id
        )
        known.insert(fingerprint)
        if !sale, HoldingPurchaseDateStore.date(for: holding.id) == nil {
            HoldingPurchaseDateStore.set(date, for: holding.id)
        }
        return true
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
            let events = activities.filter {
                $0.trade && $0.amountCents < 0 && ($0.quantity ?? 0) > 0.0000005
                    && $0.isin.caseInsensitiveCompare(symbol) == .orderedSame
            }.sorted { $0.date < $1.date }
            guard events.count >= 2 else { continue }
            let lots = HoldingLotStore.lots(for: holding.id).filter { !$0.isSale }
            guard lots.count == 1, let lump = lots.first else { continue }
            let sum = events.reduce(0.0) { $0 + ($1.quantity ?? 0) }
            let live = positions.first { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }?.quantity ?? lump.quantity
            let coversPosition = abs(lump.quantity - sum) < max(0.05, sum * 0.02) || abs(lump.quantity - live) < max(0.05, live * 0.02)
            let isOneEvent = events.contains {
                abs(($0.quantity ?? 0) - lump.quantity) < 0.0000005
                    && abs(abs($0.amountCents) - abs(lump.amountCents)) <= 150
            }
            guard coversPosition, !isOneEvent else { continue }
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
                $0.trade && $0.amountCents < 0 && ($0.quantity ?? 0) > 0.0000005
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
                let last = executions.map(\.date).max() ?? .now
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
