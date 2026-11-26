import Foundation
import LififyCore
import SwiftData

/// The editable values of a fixed cost, shared by the normal form and the form that starts from a booking.
public struct FixedCostDraft: Equatable {
    public var name: String
    public var amountText: String
    public var accountID: UUID?
    public var cadence: Cadence
    public var firstDate: Date
    public var dueRule: DueRule
    public var day: Int
    public var isActive: Bool
    public var icon: String
    /// A fixed cost that mirrors a savings plan; its schedule follows the plan.
    public var isManaged: Bool

    /// The values of an existing fixed cost, or the defaults of a new one.
    @MainActor
    public init(cost: FixedCost?) {
        name = cost?.name ?? ""
        amountText = cost.map { Self.amountText(cents: $0.amountCents) } ?? ""
        accountID = cost?.accountID
        cadence = cost?.cadence ?? .monthly
        firstDate = cost?.firstChargeDate ?? .now
        dueRule = cost?.dueRule ?? .calendarDay
        day = cost?.dayOfMonth ?? 1
        isActive = cost?.isActive ?? true
        icon = cost.map { IconPreferenceStore.icon(for: $0.id, fallback: "repeat") } ?? "repeat"
        isManaged = cost.map { SavingsPlanFixedCosts.isManagedName($0.name) } ?? false
    }

    /// The amount as the person typed it, in cents, always positive.
    public var amountCents: Int? {
        Money.cents(from: amountText).map(abs)
    }

    /// Whether the draft can be saved.
    public var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amountCents != nil
    }

    /// The amount field text for cents, with two decimals.
    public static func amountText(cents: Int) -> String {
        String(format: "%.2f", Double(abs(cents)) / 100)
    }

    /// Writes the draft into a fixed cost, inserting a new one, and saves.
    ///
    /// - Parameters:
    ///   - existing: The fixed cost being edited, or `nil` for a new one.
    ///   - context: The database context.
    /// - Returns: The saved fixed cost, or `nil` when the draft is incomplete.
    @MainActor
    @discardableResult
    public func save(into existing: FixedCost?, context: ModelContext) -> FixedCost? {
        guard isComplete, let cents = amountCents else { return nil }
        let title = name.trimmingCharacters(in: .whitespaces)
        let cost = existing ?? FixedCost(name: title, amountCents: cents)
        cost.name = isManaged && !SavingsPlanFixedCosts.isManagedName(title) ? "\(SavingsPlanFixedCosts.namePrefix)\(title)" : title
        cost.amountCents = cents
        cost.accountID = accountID
        cost.cadence = cadence
        cost.firstChargeDate = firstDate
        cost.dueRule = isManaged ? .calendarDay : dueRule
        cost.dayOfMonth = isManaged ? 2 : day
        cost.isActive = isActive
        if existing == nil { context.insert(cost) }
        IconPreferenceStore.set(icon, for: cost.id)
        if isManaged { SavingsPlanFixedCosts.adopt(cost) }
        try? context.save()
        if isManaged { SavingsPlanFixedCosts.sync(context: context) }
        return cost
    }
}
