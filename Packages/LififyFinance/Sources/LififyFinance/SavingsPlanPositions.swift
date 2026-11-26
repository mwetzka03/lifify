import Foundation
import LififyCore
import SwiftData

/// Gives every active savings plan a position in the depot, also before its first purchase.
///
/// The depot forecast only fills positions it knows. A plan for an ETF or share not held yet gets an
/// empty position (no shares), which today's depot hides and the forecast fills from the first
/// planned execution on.
@MainActor
public enum SavingsPlanPositions {
    /// Adds an empty position for each active plan whose ISIN is not in its depot yet.
    ///
    /// - Parameter context: The database context.
    /// - Returns: The positions that were added; they still need a price from Yahoo Finance.
    @discardableResult
    public static func ensure(context: ModelContext) -> [PortfolioHolding] {
        let holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        var added: [PortfolioHolding] = []
        for var plan in SavingsPlanStore.all() where plan.active && !plan.isin.isEmpty {
            if let id = plan.holdingID, holdings.contains(where: { $0.id == id }) { continue }
            let all = holdings + added
            if let existing = all.first(where: { holds($0, plan: plan) }) {
                if plan.holdingID != nil {
                    plan.holdingID = existing.id
                    SavingsPlanStore.upsert(plan)
                }
                continue
            }
            let position = PortfolioHolding(
                accountID: plan.portfolioAccountID,
                name: plan.name.isEmpty ? plan.isin : plan.name,
                symbol: plan.isin.uppercased(),
                quantity: 0,
                purchasePriceCents: 0,
                currentPriceCents: 0
            )
            context.insert(position)
            added.append(position)
            if plan.holdingID != nil {
                plan.holdingID = position.id
                SavingsPlanStore.upsert(plan)
            }
        }
        if !added.isEmpty { try? context.save() }
        return added
    }

    /// Says whether a position is the one a plan buys into.
    private static func holds(_ holding: PortfolioHolding, plan: SavingsPlanRecord) -> Bool {
        holding.accountID == plan.portfolioAccountID && holding.symbol.caseInsensitiveCompare(plan.isin) == .orderedSame
    }
}
