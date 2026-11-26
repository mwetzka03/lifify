import Foundation
import LififyCore
import SwiftData

/// Turns an existing booking into a fixed cost: finds the bookings of the same payee, links the chosen
/// ones, and remembers the payee so later imports assign its new bookings on their own.
@MainActor
public enum FixedCostFromBooking {
    /// Who a booking pays: the recipient IBAN when the notes carry one, otherwise the payee name.
    ///
    /// Amounts are left out on purpose, so a payee whose price changes stays one fixed cost.
    public static func payeeKey(of entry: LedgerEntry) -> String {
        let iban = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents).recipient
        if !iban.isEmpty { return "iban:" + iban }
        let name = SubscriptionDetector.payeeKey(entry.title)
        return name.isEmpty ? "" : "payee:" + name
    }

    /// The bookings that look like payments to the same payee on the same account, newest first.
    ///
    /// - Parameters:
    ///   - entry: The booking the person starts from.
    ///   - entries: All bookings.
    /// - Returns: Free expenses of that payee, the start booking included; refunds and bookings of
    ///   other fixed costs are left out.
    public static func related(to entry: LedgerEntry, in entries: [LedgerEntry]) -> [LedgerEntry] {
        let key = payeeKey(of: entry)
        guard !key.isEmpty else { return [entry] }
        let matches = entries.filter { candidate in
            candidate.id == entry.id || (
                isFreeExpense(candidate)
                    && candidate.accountID == entry.accountID
                    && payeeKey(of: candidate) == key
            )
        }
        return matches.sorted { $0.date > $1.date }
    }

    /// Creates the fixed cost from the chosen bookings and links them.
    ///
    /// - Parameters:
    ///   - name: The name of the fixed cost.
    ///   - source: The booking the person started from; its payee becomes the rule for new bookings.
    ///   - chosen: The bookings that belong to it, the source included.
    ///   - icon: The symbol picked for the fixed cost, if any.
    ///   - context: The database context.
    /// - Returns: The new fixed cost. Its amount and day follow the newest booking, its rhythm the gaps.
    @discardableResult
    public static func create(
        name: String,
        source: LedgerEntry,
        chosen: [LedgerEntry],
        icon: String?,
        context: ModelContext
    ) -> FixedCost {
        let bookings = (chosen.contains { $0.id == source.id } ? chosen : chosen + [source]).sorted { $0.date < $1.date }
        let newest = bookings.last ?? source
        let cost = FixedCost(
            name: name,
            amountCents: abs(newest.amountCents),
            accountID: newest.accountID,
            cadence: SubscriptionDetector.cadence(of: bookings.map(\.date)) ?? .monthly,
            firstChargeDate: bookings.first?.date ?? newest.date,
            dayOfMonth: Calendar.current.component(.day, from: newest.date)
        )
        context.insert(cost)
        bookings.forEach { $0.fixedCostID = cost.id }
        if let icon { IconPreferenceStore.set(icon, for: cost.id) }
        let key = payeeKey(of: source)
        if !key.isEmpty { LinkTable.set(.fixedCostPayee, key: cost.id.uuidString, value: key) }
        try? context.save()
        return cost
    }

    /// Assigns newly imported bookings to the fixed cost whose payee they pay.
    ///
    /// Only the given new bookings are touched and only while they have no fixed cost, so an
    /// assignment the person removed or changed by hand is never overwritten by a later import.
    ///
    /// - Parameters:
    ///   - newEntries: The bookings this import inserted.
    ///   - costs: The fixed costs.
    /// - Returns: How many bookings were assigned.
    @discardableResult
    public static func assign(newEntries: [LedgerEntry], costs: [FixedCost]) -> Int {
        let rules = LinkTable.map(.fixedCostPayee)
        guard !rules.isEmpty else { return 0 }
        let active = costs.filter { $0.isActive && rules[$0.id.uuidString] != nil }
        var count = 0
        for entry in newEntries where isFreeExpense(entry) {
            let key = payeeKey(of: entry)
            guard !key.isEmpty, let cost = active.first(where: { fits(entry, cost: $0, key: key, rule: rules[$0.id.uuidString]) }) else { continue }
            entry.fixedCostID = cost.id
            count += 1
        }
        return count
    }

    /// Forgets the payee rule of a deleted fixed cost.
    public static func forget(costID: UUID) {
        LinkTable.set(.fixedCostPayee, key: costID.uuidString, value: nil)
    }

    /// Whether a booking pays this fixed cost under its stored payee rule.
    private static func fits(_ entry: LedgerEntry, cost: FixedCost, key: String, rule: String?) -> Bool {
        guard rule == key else { return false }
        if let account = cost.accountID, account != entry.accountID { return false }
        if let end = cost.endChargeDate, entry.date > end { return false }
        return !ForecastMatchRejectionStore.isRejected(costID: cost.id, entryID: entry.id)
    }

    /// An expense that is no refund and belongs to no fixed cost yet.
    private static func isFreeExpense(_ entry: LedgerEntry) -> Bool {
        entry.kind == .expense && entry.fixedCostID == nil && !RefundLinkStore.isRefund(entry.id)
    }
}

/// The symbol a booking row shows: the icon picked for its fixed cost or variable cost, else its category's.
@MainActor
public enum BookingSymbol {
    /// Returns the symbol name for a booking.
    public static func name(for entry: LedgerEntry, category: BookingCategory) -> String {
        let picked = [entry.fixedCostID, entry.variableBudgetID]
            .compactMap { $0 }
            .lazy
            .compactMap(IconPreferenceStore.storedIcon(for:))
            .first
        return picked ?? category.systemImage
    }
}
