import Foundation
import LififyCore
import SwiftData

/// The IBANs and payee names whose bookings a variable cost takes on its own.
///
/// A rule that looks like an IBAN matches the recipient IBAN in a booking's notes; any other rule
/// matches when the booking's payee name contains it ("rewe" fits "REWE Markt GmbH").
@MainActor
public enum BudgetPayeeRules {
    /// The rules of a variable cost, in the order the person entered them.
    public static func rules(for budgetID: UUID) -> [String] {
        (LinkTable.map(.variableBudgetPayees)[budgetID.uuidString] ?? "")
            .split(separator: "\n")
            .map(String.init)
    }

    /// Stores the rules of a variable cost; empty or repeated rules are dropped.
    public static func set(_ rules: [String], for budgetID: UUID) {
        var seen = Set<String>()
        let cleaned = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        LinkTable.set(.variableBudgetPayees, key: budgetID.uuidString, value: cleaned.isEmpty ? nil : cleaned.joined(separator: "\n"))
    }

    /// Forgets the rules of a deleted variable cost.
    public static func remove(for budgetID: UUID) {
        LinkTable.set(.variableBudgetPayees, key: budgetID.uuidString, value: nil)
    }

    /// The rule a booking stands for: its recipient IBAN when the notes carry one, otherwise its
    /// payee name without an appended place or reference ("REWE Markt/Berlin" gives "REWE Markt").
    ///
    /// - Parameter entry: A booking the person picked.
    /// - Returns: The rule, or `nil` when the name is too short to match safely.
    public static func rule(from entry: LedgerEntry) -> String? {
        let iban = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents).recipient
        if isIBAN(iban) { return iban }
        let head = entry.title.split(whereSeparator: { $0 == "/" || $0 == "|" }).first.map(String.init) ?? entry.title
        let name = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return SubscriptionDetector.payeeKey(name).count >= 3 ? name : nil
    }

    /// Gives picked bookings to a variable cost, leaving every booking that already has an assignment.
    ///
    /// - Parameters:
    ///   - entries: The bookings the person picked.
    ///   - budgetID: The variable cost.
    /// - Returns: How many bookings were assigned.
    @discardableResult
    public static func assign(_ entries: [LedgerEntry], to budgetID: UUID) -> Int {
        let free = entries.filter {
            $0.kind == .expense && $0.fixedCostID == nil && $0.variableBudgetID == nil
                && $0.shoppingItemID == nil && !RefundLinkStore.isRefund($0.id)
        }
        free.forEach { $0.variableBudgetID = budgetID }
        return free.count
    }

    /// Says whether a rule is an IBAN rather than a name.
    public static func isIBAN(_ rule: String) -> Bool {
        let value = normalizedIBAN(rule)
        return (15...34).contains(value.count)
            && value.prefix(2).allSatisfy(\.isLetter)
            && value.dropFirst(2).prefix(2).allSatisfy(\.isNumber)
            && value.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Says whether a booking fits one rule.
    ///
    /// - Parameters:
    ///   - rule: An IBAN or a payee name.
    ///   - entry: The booking.
    /// - Returns: `true` for the same recipient IBAN, or a payee name that contains the rule's name.
    public static func fits(_ rule: String, entry: LedgerEntry) -> Bool {
        if isIBAN(rule) {
            let recipient = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents).recipient
            return !recipient.isEmpty && recipient == normalizedIBAN(rule)
        }
        let name = SubscriptionDetector.payeeKey(rule)
        guard name.count >= 3 else { return false }
        return SubscriptionDetector.payeeKey(entry.title).contains(name)
    }

    /// The variable cost whose rules fit a booking, if any.
    ///
    /// - Parameters:
    ///   - entry: The booking.
    ///   - budgets: All variable costs, in the order they are checked.
    /// - Returns: The first variable cost with a fitting rule that also covers the booking's account.
    public static func budget(for entry: LedgerEntry, in budgets: [VariableBudget]) -> VariableBudget? {
        budgets.first { budget in
            if let accounts = VariableBudgetAccounts.storedIDs(for: budget.id), !accounts.isEmpty,
               let account = entry.accountID, !accounts.contains(account) {
                return false
            }
            return rules(for: budget.id).contains { fits($0, entry: entry) }
        }
    }

    /// The IBAN in a comparable form: upper case, without spaces.
    private static func normalizedIBAN(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace }
    }
}

/// Where a booking is assigned: nowhere, to a fixed cost, or to a variable cost.
public enum BookingTarget: Hashable, Sendable {
    case none
    case fixedCost(UUID)
    case variableBudget(UUID)

    /// The current target of a booking.
    public init(of entry: LedgerEntry) {
        if let id = entry.fixedCostID {
            self = .fixedCost(id)
        } else if let id = entry.variableBudgetID {
            self = .variableBudget(id)
        } else {
            self = .none
        }
    }

    /// Writes the target into a booking; a booking belongs to at most one of them.
    public func apply(to entry: LedgerEntry) {
        switch self {
        case .none:
            entry.fixedCostID = nil
            entry.variableBudgetID = nil
        case .fixedCost(let id):
            entry.fixedCostID = id
            entry.variableBudgetID = nil
        case .variableBudget(let id):
            entry.fixedCostID = nil
            entry.variableBudgetID = id
        }
    }
}

/// Applies the automatic assignments of fixed costs and variable costs to new bookings.
@MainActor
public enum BookingAutoAssign {
    /// Assigns new bookings by the payee rules: a fixed cost first, then a variable cost.
    ///
    /// Only free expenses are touched, so a choice the person made is never overwritten.
    ///
    /// - Parameters:
    ///   - entries: The new bookings.
    ///   - context: The database context, to read fixed and variable costs.
    /// - Returns: The bookings that got an assignment.
    @discardableResult
    public static func apply(to entries: [LedgerEntry], context: ModelContext) -> [LedgerEntry] {
        let costs = (try? context.fetch(FetchDescriptor<FixedCost>())) ?? []
        let budgets = (try? context.fetch(FetchDescriptor<VariableBudget>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let free = entries.filter(isFree)
        FixedCostFromBooking.assign(newEntries: free, costs: costs)
        for entry in free where entry.fixedCostID == nil {
            entry.variableBudgetID = BudgetPayeeRules.budget(for: entry, in: budgets)?.id
        }
        return free.filter { $0.fixedCostID != nil || $0.variableBudgetID != nil }
    }

    /// An expense without any assignment that is no refund.
    private static func isFree(_ entry: LedgerEntry) -> Bool {
        entry.kind == .expense && entry.fixedCostID == nil && entry.variableBudgetID == nil
            && entry.shoppingItemID == nil && !RefundLinkStore.isRefund(entry.id)
    }
}

/// Bookings the person should still look at: automatic assignments of an import, and every booking
/// that came from a bank notice since the app was last opened.
///
/// It is a short-lived to-do list, not data, so it is not part of a backup.
@MainActor
public enum AssignmentInbox {
    /// Where a waiting booking came from.
    public enum Source: String, Sendable {
        case bankImport = "import"
        case notice
    }

    /// Adds bookings to the list.
    public static func add(_ ids: [UUID], source: Source) {
        guard !ids.isEmpty else { return }
        var map = LinkTable.map(.assignmentInbox)
        ids.forEach { map[$0.uuidString] = source.rawValue }
        LinkTable.replace(.assignmentInbox, with: map)
    }

    /// The waiting bookings of one source that still exist, oldest first.
    public static func pending(_ source: Source, in entries: [LedgerEntry]) -> [LedgerEntry] {
        let ids = Set(LinkTable.map(.assignmentInbox).filter { $0.value == source.rawValue }.keys)
        return entries.filter { ids.contains($0.id.uuidString) }.sorted { $0.date < $1.date }
    }

    /// The sources with waiting bookings that still exist, reading the stored list afresh, because a
    /// notice may have been booked by a shortcut while the app was in the background.
    ///
    /// - Parameter context: The database context.
    /// - Returns: The sources in the order notices, import.
    public static func waitingSources(context: ModelContext) -> [Source] {
        LinkTable.clearCache()
        let map = LinkTable.map(.assignmentInbox)
        let ids = map.keys.compactMap(UUID.init(uuidString:))
        guard !ids.isEmpty else { return [] }
        let found = (try? context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let present = Set(found.map(\.id.uuidString))
        // Bookings deleted in the meantime leave the list for good.
        let gone = ids.filter { !present.contains($0.uuidString) }
        if !gone.isEmpty { clear(gone) }
        let sources = Set(map.filter { present.contains($0.key) }.values)
        return [Source.notice, .bankImport].filter { sources.contains($0.rawValue) }
    }

    /// Takes bookings off the list after the person looked at them.
    public static func clear(_ ids: [UUID]) {
        var map = LinkTable.map(.assignmentInbox)
        ids.forEach { map.removeValue(forKey: $0.uuidString) }
        LinkTable.replace(.assignmentInbox, with: map)
    }
}
