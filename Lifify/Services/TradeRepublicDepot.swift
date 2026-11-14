import Foundation
import SwiftData

@MainActor
enum TradeRepublicDepotApplier {
    /// Writes positions the session actually returned. An empty reply leaves the depot untouched.
    @discardableResult
    static func apply(positions: [TradeRepublicPosition], context: ModelContext) throws -> Int {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let named = accounts.map {
            NamedAccount(id: $0.id, name: $0.name, kind: $0.kind, isMain: $0.isMain)
        }
        let tradeRepublic = accounts.first {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }
        let linked = tradeRepublic.flatMap { PortfolioLinkStore.portfolioID(for: $0.id) }
        let choice = TradeRepublicDepotTarget.choose(accounts: named, linkedPortfolioID: linked)
        let portfolioID: UUID?
        if case .existing(let id) = choice { portfolioID = id } else { portfolioID = nil }
        let stored = try context.fetch(FetchDescriptor<PortfolioHolding>())
        let mine = stored.filter { $0.accountID == portfolioID }
        let seeds = mine.map {
            HoldingSeed(symbol: $0.symbol, name: $0.name, quantity: $0.quantity, purchasePriceCents: $0.purchasePriceCents)
        }
        let edits = TradeRepublicDepotPlan.edits(positions: positions, holdings: seeds)
        guard !edits.isEmpty else { return 0 }
        let portfolio: Account
        switch choice {
        case .ambiguous:
            throw TradeRepublicFailure.noSingleDepot
        case .existing(let id):
            guard let found = accounts.first(where: { $0.id == id }) else {
                throw TradeRepublicFailure.noSingleDepot
            }
            portfolio = found
            if PortfolioLinkStore.checkingID(for: found.id) == nil, let tradeRepublic {
                PortfolioLinkStore.link(portfolio: found.id, to: tradeRepublic.id)
            }
        case .create:
            let checking = tradeRepublic ?? makeChecking(context: context)
            let created = Account(name: L("Depot", "Portfolio"), kind: .portfolio, isLiquid: false)
            context.insert(created)
            PortfolioLinkStore.link(portfolio: created.id, to: checking.id)
            portfolio = created
        }
        for edit in edits {
            if let holding = mine.first(where: { $0.symbol.caseInsensitiveCompare(edit.symbol) == .orderedSame }) {
                holding.symbol = edit.symbol
                holding.name = edit.name
                holding.quantity = edit.quantity
                holding.purchasePriceCents = edit.purchasePriceCents
                holding.updatedAt = .now
            } else if edit.isNew {
                context.insert(PortfolioHolding(
                    accountID: portfolio.id,
                    name: edit.name,
                    symbol: edit.symbol,
                    quantity: edit.quantity,
                    purchasePriceCents: edit.purchasePriceCents,
                    currentPriceCents: 0
                ))
            }
        }
        try context.save()
        return edits.count
    }

    private static func makeChecking(context: ModelContext) -> Account {
        let account = Account(name: "Trade Republic", kind: .checking, isLiquid: true, isMain: false)
        context.insert(account)
        return account
    }
}
