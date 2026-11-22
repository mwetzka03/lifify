import Foundation
import SwiftData

@Model
public final class FixedCost {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var amountCents: Int
    public var accountID: UUID?
    public var cadenceRaw: String
    public var firstChargeDate: Date
    public var endChargeDate: Date?
    public var dueRuleRaw: String
    public var dayOfMonth: Int
    public var isActive: Bool

    public var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }
    public var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int,
        accountID: UUID? = nil,
        cadence: Cadence = .monthly,
        firstChargeDate: Date = .now,
        endChargeDate: Date? = nil,
        dueRule: DueRule = .calendarDay,
        dayOfMonth: Int = 1,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.accountID = accountID
        self.cadenceRaw = cadence.rawValue
        self.firstChargeDate = firstChargeDate
        self.endChargeDate = endChargeDate
        self.dueRuleRaw = dueRule.rawValue
        self.dayOfMonth = dayOfMonth
        self.isActive = isActive
    }
}

@Model
public final class VariableBudget {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var monthlyAmountCents: Int
    public var accountID: UUID?
    public var notes: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        monthlyAmountCents: Int,
        accountID: UUID? = nil,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.monthlyAmountCents = monthlyAmountCents
        self.accountID = accountID
        self.notes = notes
        self.createdAt = createdAt
    }
}

@Model
public final class BudgetPool {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var amountCents: Int
    public var accountID: UUID?
    public var periodModeRaw: String
    public var salaryStartDay: Int
    public var isScalable: Bool
    public var isActive: Bool
    public var createdAt: Date

    public var periodMode: BudgetPeriodMode {
        get { BudgetPeriodMode(rawValue: periodModeRaw) ?? .salaryPeriod }
        set { periodModeRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int,
        accountID: UUID? = nil,
        periodMode: BudgetPeriodMode = .salaryPeriod,
        salaryStartDay: Int = 1,
        isScalable: Bool = false,
        isActive: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.accountID = accountID
        self.periodModeRaw = periodMode.rawValue
        self.salaryStartDay = salaryStartDay
        self.isScalable = isScalable
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

@Model
public final class IncomeForecast {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var amountCents: Int
    public var accountID: UUID?
    public var cadenceRaw: String
    public var firstPaymentDate: Date
    public var endPaymentDate: Date?
    public var dueRuleRaw: String
    public var dayOfMonth: Int
    public var isActive: Bool

    public var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }
    public var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        amountCents: Int,
        accountID: UUID? = nil,
        cadence: Cadence = .monthly,
        firstPaymentDate: Date = .now,
        endPaymentDate: Date? = nil,
        dueRule: DueRule = .calendarDay,
        dayOfMonth: Int = 1,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.amountCents = amountCents
        self.accountID = accountID
        self.cadenceRaw = cadence.rawValue
        self.firstPaymentDate = firstPaymentDate
        self.endPaymentDate = endPaymentDate
        self.dueRuleRaw = dueRule.rawValue
        self.dayOfMonth = dayOfMonth
        self.isActive = isActive
    }
}
