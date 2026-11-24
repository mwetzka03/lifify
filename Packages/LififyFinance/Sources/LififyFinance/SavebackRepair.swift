import Foundation
import LififyCore
import SwiftData

/// Turns Trade Republic Saveback that was booked as a purchase into cashback.
///
/// Saveback buys shares with Trade Republic's money, not the person's. Earlier versions booked
/// it as a transfer from the cash account into the depot, which lowered the cash balance and
/// counted the shares at cost. Repaired, it is income on the depot like any cashback, and its
/// shares count with no purchase cost, so their whole value shows as gain.
@MainActor
public enum SavebackRepair {
    /// Repairs every Saveback booked as a purchase. Running it again changes nothing.
    ///
    /// - Parameter context: The database context.
    /// - Returns: The number of repaired bookings.
    @discardableResult
    public static func run(context: ModelContext) -> Int {
        let entries = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let holdings = (try? context.fetch(FetchDescriptor<PortfolioHolding>())) ?? []
        var repaired = 0
        for entry in entries where isSavebackPurchase(entry) {
            guard let depotID = entry.toAccountID,
                  accounts.first(where: { $0.id == depotID })?.kind == .portfolio else { continue }
            rewrite(entry, depotID: depotID)
            markLots(of: entry, holdings: holdings, context: context)
            repaired += 1
        }
        if repaired > 0 { try? context.save() }
        return repaired
    }

    /// Says whether a booking is a Saveback that was booked as a purchase.
    public static func isSavebackPurchase(_ entry: LedgerEntry) -> Bool {
        guard entry.kind == .transfer else { return false }
        return entry.notes.uppercased().replacingOccurrences(of: "_", with: "").contains("SAVEBACK")
    }

    /// Makes the booking a cashback income on the depot.
    private static func rewrite(_ entry: LedgerEntry, depotID: UUID) {
        var name = entry.title
        for prefix in ["Kauf: ", "Purchase: ", "Buy: ", "Sparplan: ", "Savings plan: "] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
        }
        entry.title = "Cashback: \(name)"
        entry.kind = .income
        entry.amountCents = abs(entry.amountCents)
        entry.accountID = depotID
        entry.fromAccountID = nil
        entry.toAccountID = nil
        entry.notes = entry.notes.replacingOccurrences(of: "Typ: Handel", with: "Typ: Cashback")
        if !entry.notes.contains("Typ: Cashback") {
            entry.notes = "Typ: Cashback\n" + entry.notes
        }
    }

    /// Marks the shares of that booking as cashback, so they carry no purchase cost.
    private static func markLots(of entry: LedgerEntry, holdings: [PortfolioHolding], context: ModelContext) {
        for holding in holdings {
            var lots = HoldingLotStore.lots(for: holding.id)
            guard let index = lots.firstIndex(where: { lot in
                !lot.isSale && lot.source.isEmpty
                    && (lot.ledgerEntryID == entry.id
                        || (abs(lot.date.timeIntervalSince(entry.date)) < 120 && lot.amountCents == abs(entry.amountCents)))
            }) else { continue }
            lots[index].source = "cashback"
            HoldingLotStore.replace(lots, holdingID: holding.id)
            _ = HoldingMaintenance.sync(holding, context: context)
            return
        }
    }
}
