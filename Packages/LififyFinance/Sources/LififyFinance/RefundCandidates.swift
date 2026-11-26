import Foundation
import LififyCore

/// Finds the expenses an income can be linked to as a refund.
@MainActor
public enum RefundCandidates {
    /// The expenses of the year before the income, split into suggestions and the rest.
    public struct Groups: Equatable {
        /// Expenses of the same payee or the same IBAN, newest first.
        public let suggested: [LedgerEntry]
        /// All other expenses, newest first.
        public let others: [LedgerEntry]
    }

    /// Splits the possible expenses into suggestions and all others.
    ///
    /// - Parameters:
    ///   - income: The income the person wants to mark as a refund.
    ///   - entries: All bookings.
    ///   - limit: The most expenses to offer in all.
    /// - Returns: Expenses that are no refunds themselves and lie on or before the income's day.
    ///   A suggestion pays the IBAN the income came from, or carries the same payee name.
    public static func groups(for income: LedgerEntry, in entries: [LedgerEntry], limit: Int = 80) -> Groups {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: income.date)) ?? income.date
        let start = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        let candidates = entries
            .filter { entry in
                entry.kind == .expense && entry.id != income.id && entry.date >= start && entry.date < end
                    && !RefundLinkStore.isRefund(entry.id)
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        let match = Matcher(income: income)
        let suggested = candidates.filter(match.fits)
        let others = candidates.filter { !match.fits($0) }
        return Groups(suggested: suggested, others: others)
    }

    /// All possible expenses, suggestions first.
    public static func expenses(for income: LedgerEntry, in entries: [LedgerEntry], limit: Int = 80) -> [LedgerEntry] {
        let groups = groups(for: income, in: entries, limit: limit)
        return groups.suggested + groups.others
    }

    /// Says whether an expense belongs to the same counterparty as the income.
    @MainActor
    private struct Matcher {
        let payee: String
        let iban: String

        init(income: LedgerEntry) {
            payee = SubscriptionDetector.payeeKey(income.title)
            iban = BankImportService.ibans(from: income.notes, amountCents: income.amountCents).sender
        }

        /// A refund often adds a word ("Zalando Erstattung"), so one name starting with the other counts.
        func fits(_ expense: LedgerEntry) -> Bool {
            if !iban.isEmpty, BankImportService.ibans(from: expense.notes, amountCents: expense.amountCents).recipient == iban {
                return true
            }
            let other = SubscriptionDetector.payeeKey(expense.title)
            guard min(payee.count, other.count) >= 3 else { return false }
            return payee.hasPrefix(other) || other.hasPrefix(payee)
        }
    }
}
