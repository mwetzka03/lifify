import Foundation
import LififyCore

/// Finds the expenses an income can be linked to as a refund.
@MainActor
public enum RefundCandidates {
    /// Expenses of the year before the income, the same payee first, then the newest.
    ///
    /// - Parameters:
    ///   - income: The income the person wants to mark as a refund.
    ///   - entries: All bookings.
    ///   - limit: The most expenses to offer.
    /// - Returns: Expenses that are no refunds themselves and lie on or before the income's day.
    public static func expenses(for income: LedgerEntry, in entries: [LedgerEntry], limit: Int = 60) -> [LedgerEntry] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: income.date)) ?? income.date
        let start = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        let payee = SubscriptionDetector.payeeKey(income.title)
        let candidates = entries.filter { entry in
            entry.kind == .expense && entry.id != income.id && entry.date >= start && entry.date < end
                && !RefundLinkStore.isRefund(entry.id)
        }
        // A refund often adds a word ("Zalando Erstattung"), so one name starting with the other counts.
        let samePayee = { (entry: LedgerEntry) -> Bool in
            let other = SubscriptionDetector.payeeKey(entry.title)
            guard min(payee.count, other.count) >= 3 else { return false }
            return payee.hasPrefix(other) || other.hasPrefix(payee)
        }
        return candidates
            .sorted { lhs, rhs in
                let left = samePayee(lhs), right = samePayee(rhs)
                return left != right ? left : lhs.date > rhs.date
            }
            .prefix(limit)
            .map { $0 }
    }
}
