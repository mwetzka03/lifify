import Foundation
import LififyCore
import SwiftData

/// The IBANs and payee names whose bookings a variable cost takes on its own.
///
/// A rule that looks like an IBAN matches the recipient IBAN in a booking's notes; any other rule
/// matches when the booking's payee name contains it ("rewe" fits "REWE Markt GmbH"). Rules ignore
/// the account. A rule belongs to one variable cost only; pools may share rules.
@MainActor
public enum BudgetPayeeRules {
    /// What a rule list belongs to; each has its own stored list.
    public enum Owner: Sendable {
        case variableBudget
        case budgetPool

        var kind: LinkKind {
            switch self {
            case .variableBudget: .variableBudgetPayees
            case .budgetPool: .budgetPoolPayees
            }
        }
    }

    /// The rules of a variable cost or a pool, in the order the person entered them.
    public static func rules(for ownerID: UUID, owner: Owner = .variableBudget) -> [String] {
        (LinkTable.map(owner.kind)[ownerID.uuidString] ?? "")
            .split(separator: "\n")
            .map(String.init)
    }

    /// Stores the rules of a variable cost or a pool; empty or repeated rules are dropped.
    ///
    /// A variable cost takes its rules over from any other variable cost, because one payee can
    /// only land in one of them. Pools keep shared rules.
    public static func set(_ rules: [String], for ownerID: UUID, owner: Owner = .variableBudget) {
        var seen = Set<String>()
        let cleaned = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        var map = LinkTable.map(owner.kind)
        if owner == .variableBudget {
            for (key, value) in map where key != ownerID.uuidString {
                let kept = value.split(separator: "\n").map(String.init).filter { !seen.contains($0.lowercased()) }
                map[key] = kept.isEmpty ? nil : kept.joined(separator: "\n")
            }
        }
        map[ownerID.uuidString] = cleaned.isEmpty ? nil : cleaned.joined(separator: "\n")
        LinkTable.replace(owner.kind, with: map)
    }

    /// The other variable cost that holds a rule today, if any.
    public static func otherOwner(of rule: String, besides ownerID: UUID?) -> UUID? {
        let key = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return LinkTable.map(.variableBudgetPayees).first { id, value in
            id != ownerID?.uuidString && value.split(separator: "\n").contains { $0.lowercased() == key }
        }.flatMap { UUID(uuidString: $0.key) }
    }

    /// Forgets the rules of a deleted variable cost or pool.
    public static func remove(for ownerID: UUID, owner: Owner = .variableBudget) {
        LinkTable.set(owner.kind, key: ownerID.uuidString, value: nil)
    }

    /// Says whether a booking fits any rule of a variable cost or pool.
    public static func fitsAny(of ownerID: UUID, owner: Owner, entry: LedgerEntry) -> Bool {
        rules(for: ownerID, owner: owner).contains { fits($0, entry: entry) }
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

    /// The distinct payees among the expenses, one per rule, newest payment first.
    ///
    /// - Parameter entries: All bookings.
    /// - Returns: One group per IBAN or payee name with how often and when it was last paid.
    public static func payeeGroups(in entries: [LedgerEntry]) -> [PayeeGroup] {
        var groups: [String: PayeeGroup] = [:]
        for entry in entries where entry.kind == .expense && !RefundLinkStore.isRefund(entry.id) {
            guard let rule = rule(from: entry) else { continue }
            let key = rule.lowercased()
            var group = groups[key] ?? PayeeGroup(rule: rule, sampleTitle: entry.title, count: 0, totalCents: 0, lastDate: entry.date)
            group.count += 1
            group.totalCents += abs(entry.amountCents)
            if entry.date >= group.lastDate {
                group.lastDate = entry.date
                group.sampleTitle = entry.title
            }
            groups[key] = group
        }
        return groups.values.sorted { $0.lastDate > $1.lastDate }
    }

    /// Gives every existing free expense that fits the variable cost's rules to it, so a new rule
    /// also covers the past.
    ///
    /// - Parameters:
    ///   - budget: The variable cost with its stored rules.
    ///   - entries: All bookings.
    /// - Returns: How many bookings were assigned.
    @discardableResult
    public static func applyToExisting(_ budget: VariableBudget, entries: [LedgerEntry]) -> Int {
        assign(entries.filter { self.budget(for: $0, in: [budget]) != nil }, to: budget)
    }

    /// Gives bookings to a variable cost, leaving every booking that already has an assignment,
    /// and adds each booking's account to the cost's accounts when it is limited to others.
    ///
    /// - Parameters:
    ///   - entries: The bookings.
    ///   - budget: The variable cost.
    /// - Returns: How many bookings were assigned.
    @discardableResult
    public static func assign(_ entries: [LedgerEntry], to budget: VariableBudget) -> Int {
        let free = entries.filter {
            $0.kind == .expense && $0.fixedCostID == nil && $0.variableBudgetID == nil
                && $0.shoppingItemID == nil && !RefundLinkStore.isRefund($0.id)
        }
        for entry in free {
            entry.variableBudgetID = budget.id
            VariableBudgetAccounts.include(entry.accountID, in: budget)
        }
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

    /// The variable cost whose rules fit a booking, on any account.
    ///
    /// - Parameters:
    ///   - entry: The booking.
    ///   - budgets: All variable costs, in the order they are checked.
    /// - Returns: The first variable cost with a fitting rule.
    public static func budget(for entry: LedgerEntry, in budgets: [VariableBudget]) -> VariableBudget? {
        budgets.first { budget in rules(for: budget.id).contains { fits($0, entry: entry) } }
    }

    /// The IBAN in a comparable form: upper case, without spaces.
    private static func normalizedIBAN(_ value: String) -> String {
        value.uppercased().filter { !$0.isWhitespace }
    }
}

/// One payee among the expenses, as offered when rules are picked from bookings.
public struct PayeeGroup: Identifiable, Equatable, Sendable {
    /// The rule the payee gives: its IBAN or its name.
    public let rule: String
    /// The title of the newest booking, to recognize the payee.
    public var sampleTitle: String
    /// How many expenses went to the payee.
    public var count: Int
    /// The sum of those expenses, positive.
    public var totalCents: Int
    /// The day of the newest one.
    public var lastDate: Date

    public var id: String { rule.lowercased() }
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
    ///
    /// Variable cost splits of the booking go away, because the target now holds its whole amount.
    @MainActor
    public func apply(to entry: LedgerEntry, context: ModelContext) {
        VariableShares.removeSplits(of: entry, context: context)
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

/// How a booking's amount is shared among variable costs: one cost with the whole amount is stored
/// as the booking's direct variable cost, several shares as splits. The booking form always shows
/// them as splits, so a whole assignment appears there with the full amount.
@MainActor
public enum VariableShares {
    /// The shares of a booking: its splits, or its direct variable cost with the whole amount.
    public static func shares(of entry: LedgerEntry, splits: [TransactionSplit]) -> [(targetID: UUID, amount: Int)] {
        let own = splits.filter { $0.transactionID == entry.id && $0.kind == .variableBudget }
        if !own.isEmpty { return own.map { ($0.targetID, $0.amountCents) } }
        return entry.variableBudgetID.map { [($0, abs(entry.amountCents))] } ?? []
    }

    /// Splits how shares are stored.
    ///
    /// - Parameter shares: The shares the person entered.
    /// - Returns: A direct variable cost when one cost takes everything, otherwise the splits to store.
    public static func storage(_ shares: [(targetID: UUID, amount: Int)]) -> (direct: UUID?, splits: [(targetID: UUID, amount: Int)]) {
        let targets = Set(shares.map(\.targetID))
        if targets.count == 1, let only = targets.first { return (only, []) }
        return (nil, shares)
    }

    /// Removes the variable cost splits of a booking.
    public static func removeSplits(of entry: LedgerEntry, context: ModelContext) {
        let id = entry.id
        let kind = SplitKind.variableBudget.rawValue
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>(predicate: #Predicate { $0.transactionID == id && $0.kindRaw == kind }))) ?? []
        splits.forEach(context.delete)
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
            if let budget = BudgetPayeeRules.budget(for: entry, in: budgets) {
                BudgetPayeeRules.assign([entry], to: budget)
            }
        }
        let budgeted = free.filter { $0.fixedCostID != nil || $0.variableBudgetID != nil }
        // Pools are a separate layer: a booking can count for a pool and a cost at once.
        let pooled = PoolPayeeRules.assign(entries, context: context)
        return entries.filter { entry in budgeted.contains { $0.id == entry.id } || pooled.contains { $0.id == entry.id } }
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

/// Gives expenses to budget pools by the pools' IBAN and name rules, as a split over the whole amount.
@MainActor
public enum PoolPayeeRules {
    /// The first active pool whose rules fit a booking.
    public static func pool(for entry: LedgerEntry, in pools: [BudgetPool]) -> BudgetPool? {
        pools.first { $0.isActive && BudgetPayeeRules.fitsAny(of: $0.id, owner: .budgetPool, entry: entry) }
    }

    /// Adds a pool split to new expenses that fit a pool and are in no pool yet.
    ///
    /// - Parameters:
    ///   - entries: The new bookings.
    ///   - context: The database context.
    /// - Returns: The bookings that got a pool.
    @discardableResult
    public static func assign(_ entries: [LedgerEntry], context: ModelContext) -> [LedgerEntry] {
        let pools = (try? context.fetch(FetchDescriptor<BudgetPool>(sortBy: [SortDescriptor(\.name)]))) ?? []
        guard pools.contains(where: { !BudgetPayeeRules.rules(for: $0.id, owner: .budgetPool).isEmpty }) else { return [] }
        let pooled = pooledIDs(context: context)
        var assigned: [LedgerEntry] = []
        for entry in entries where isCandidate(entry) && !pooled.contains(entry.id) {
            guard let pool = pool(for: entry, in: pools) else { continue }
            add(entry, to: pool, context: context)
            assigned.append(entry)
        }
        return assigned
    }

    /// Gives every earlier expense that fits the pool's rules and is in no pool yet to it.
    ///
    /// - Parameters:
    ///   - pool: The pool with its stored rules.
    ///   - entries: All bookings.
    ///   - context: The database context.
    /// - Returns: How many bookings were added.
    @discardableResult
    public static func applyToExisting(_ pool: BudgetPool, entries: [LedgerEntry], context: ModelContext) -> Int {
        let pooled = pooledIDs(context: context)
        let fitting = entries.filter {
            isCandidate($0) && !pooled.contains($0.id) && BudgetPayeeRules.fitsAny(of: pool.id, owner: .budgetPool, entry: $0)
        }
        fitting.forEach { add($0, to: pool, context: context) }
        return fitting.count
    }

    /// The pool a booking counts for, if any.
    public static func poolID(of entry: LedgerEntry, context: ModelContext) -> UUID? {
        let id = entry.id
        let pool = SplitKind.budgetPool.rawValue
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>(predicate: #Predicate { $0.transactionID == id && $0.kindRaw == pool }))) ?? []
        return splits.first?.targetID
    }

    /// Moves a booking into another pool or out of every pool, by hand.
    ///
    /// - Parameters:
    ///   - pool: The new pool, or `nil` to take the booking out of its pool.
    ///   - entry: The booking.
    ///   - context: The database context.
    public static func setPool(_ pool: BudgetPool?, for entry: LedgerEntry, context: ModelContext) {
        let id = entry.id
        let kind = SplitKind.budgetPool.rawValue
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>(predicate: #Predicate { $0.transactionID == id && $0.kindRaw == kind }))) ?? []
        splits.forEach(context.delete)
        if let pool { add(entry, to: pool, context: context) }
    }

    /// Books the whole amount of an expense into a pool, in the pool's period of the booking.
    private static func add(_ entry: LedgerEntry, to pool: BudgetPool, context: ModelContext) {
        context.insert(TransactionSplit(
            transactionID: entry.id,
            targetID: pool.id,
            kind: .budgetPool,
            periodKey: CalendarService.periodKey(for: entry.date, pool: pool),
            amountCents: abs(entry.amountCents)
        ))
    }

    /// The bookings that already count for a pool.
    private static func pooledIDs(context: ModelContext) -> Set<UUID> {
        let pool = SplitKind.budgetPool.rawValue
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>(predicate: #Predicate { $0.kindRaw == pool }))) ?? []
        return Set(splits.map(\.transactionID))
    }

    /// An expense with an amount that is no refund.
    private static func isCandidate(_ entry: LedgerEntry) -> Bool {
        entry.kind == .expense && entry.amountCents != 0 && !RefundLinkStore.isRefund(entry.id)
    }
}

