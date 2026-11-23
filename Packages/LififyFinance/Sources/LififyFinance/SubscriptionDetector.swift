import Foundation
import LififyCore
import SwiftData

/// A repeated payment that could become a fixed cost.
public struct SubscriptionSuggestion: Identifiable, Equatable {
    /// The normalized payee, which also identifies a rejection.
    public let id: String
    public let title: String
    public let amountCents: Int
    public let cadence: Cadence
    public let occurrences: Int
    public let lastDate: Date
    public let accountID: UUID?
    public let entryIDs: [UUID]
}

/// Finds repeated payments that are not fixed costs yet.
@MainActor
public enum SubscriptionDetector {
    /// The fewest payments that count as a pattern.
    public static let minimumOccurrences = 3
    /// The allowed amount difference from the typical payment.
    public static let amountTolerance = 0.10

    /// Lists the suggestions, largest amount first.
    ///
    /// - Parameters:
    ///   - entries: All bookings.
    ///   - costs: The existing fixed costs.
    ///   - now: The current time, used to ignore ended subscriptions.
    /// - Returns: Patterns that are neither fixed costs nor rejected.
    public static func suggestions(
        entries: [LedgerEntry],
        costs: [FixedCost],
        now: Date = FinanceClock.now
    ) -> [SubscriptionSuggestion] {
        let taken = Set(costs.map { payeeKey($0.name) })
        let rejected = LinkTable.map(.subscriptionRejection)
        let candidates = entries.filter { $0.kind == .expense && $0.fixedCostID == nil && !RefundLinkStore.isRefund($0.id) }
        let groups = Dictionary(grouping: candidates) { payeeKey($0.title) }
        return groups.compactMap { key, rows -> SubscriptionSuggestion? in
            guard key.count >= 3, !taken.contains(key), rejected[key] == nil else { return nil }
            return suggestion(key: key, rows: rows, now: now)
        }
        .sorted { $0.amountCents != $1.amountCents ? $0.amountCents > $1.amountCents : $0.title < $1.title }
    }

    /// Remembers that a suggestion is not wanted.
    public static func reject(_ suggestion: SubscriptionSuggestion) {
        LinkTable.set(.subscriptionRejection, key: suggestion.id, value: "1")
    }

    /// Creates the fixed cost of a suggestion and links its past payments.
    ///
    /// - Parameters:
    ///   - suggestion: The accepted suggestion.
    ///   - entries: All bookings.
    ///   - context: The database context.
    /// - Returns: The new fixed cost.
    @discardableResult
    public static func adopt(_ suggestion: SubscriptionSuggestion, entries: [LedgerEntry], context: ModelContext) -> FixedCost {
        let linked = entries.filter { suggestion.entryIDs.contains($0.id) }
        let first = linked.map(\.date).min() ?? suggestion.lastDate
        let cost = FixedCost(
            name: suggestion.title,
            amountCents: suggestion.amountCents,
            accountID: suggestion.accountID,
            cadence: suggestion.cadence,
            firstChargeDate: first,
            dayOfMonth: Calendar.current.component(.day, from: suggestion.lastDate)
        )
        context.insert(cost)
        linked.forEach { $0.fixedCostID = cost.id }
        try? context.save()
        return cost
    }

    /// Reduces a title to its main payee, ignoring case, accents, and appended places.
    public static func payeeKey(_ title: String) -> String {
        let head = title.split(whereSeparator: { $0 == "/" || $0 == "|" }).first.map(String.init) ?? title
        let folded = head.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }

    /// Builds a suggestion when a payee's payments have a stable amount and rhythm.
    private static func suggestion(key: String, rows: [LedgerEntry], now: Date) -> SubscriptionSuggestion? {
        let typical = median(rows.map { abs($0.amountCents) })
        let similar = rows
            .filter { Double(abs(abs($0.amountCents) - typical)) <= Double(typical) * amountTolerance }
            .sorted { $0.date < $1.date }
        guard similar.count >= minimumOccurrences,
              let cadence = cadence(of: similar.map(\.date)),
              let last = similar.last,
              isStillRunning(last.date, cadence: cadence, now: now)
        else { return nil }
        return SubscriptionSuggestion(
            id: key,
            title: last.title,
            amountCents: median(similar.map { abs($0.amountCents) }),
            cadence: cadence,
            occurrences: similar.count,
            lastDate: last.date,
            accountID: last.accountID,
            entryIDs: similar.map(\.id)
        )
    }

    /// Returns the rhythm that fits every gap between the payments.
    private static func cadence(of dates: [Date]) -> Cadence? {
        let calendar = Calendar.current
        let gaps = zip(dates, dates.dropFirst()).compactMap { pair in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: pair.0), to: calendar.startOfDay(for: pair.1)).day
        }
        guard !gaps.isEmpty else { return nil }
        return [Cadence.weekly, .biweekly, .monthly, .yearly].first { cadence in
            let range = gapRange(cadence)
            return gaps.allSatisfy(range.contains)
        }
    }

    /// The gaps in days that count as a rhythm, with room for weekends and bank holidays.
    private static func gapRange(_ cadence: Cadence) -> ClosedRange<Int> {
        switch cadence {
        case .weekly: 6...8
        case .biweekly: 13...15
        case .monthly: 27...34
        case .yearly: 358...372
        }
    }

    /// A pattern counts only while its next payment is at most half a rhythm overdue.
    private static func isStillRunning(_ last: Date, cadence: Cadence, now: Date) -> Bool {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return Double(days) <= Double(gapRange(cadence).upperBound) * 1.5
    }

    /// Returns the middle value.
    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}
