import Foundation
import SwiftData

@Model
final class FixedCost {
    @Attribute(.unique) var id: UUID
    var name: String
    var amountCents: Int
    var accountID: UUID?
    var cadenceRaw: String
    var firstChargeDate: Date
    var endChargeDate: Date?
    var dueRuleRaw: String
    var dayOfMonth: Int
    var isActive: Bool

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }
    var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    init(
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
final class VariableBudget {
    @Attribute(.unique) var id: UUID
    var name: String
    var monthlyAmountCents: Int
    var accountID: UUID?
    var notes: String
    var createdAt: Date

    init(
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
final class BudgetPool {
    @Attribute(.unique) var id: UUID
    var name: String
    var amountCents: Int
    var accountID: UUID?
    var periodModeRaw: String
    var salaryStartDay: Int
    var isScalable: Bool
    var isActive: Bool
    var createdAt: Date

    var periodMode: BudgetPeriodMode {
        get { BudgetPeriodMode(rawValue: periodModeRaw) ?? .salaryPeriod }
        set { periodModeRaw = newValue.rawValue }
    }

    init(
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
final class IncomeForecast {
    @Attribute(.unique) var id: UUID
    var name: String
    var amountCents: Int
    var accountID: UUID?
    var cadenceRaw: String
    var firstPaymentDate: Date
    var endPaymentDate: Date?
    var dueRuleRaw: String
    var dayOfMonth: Int
    var isActive: Bool

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }
    var dueRule: DueRule {
        get { DueRule(rawValue: dueRuleRaw) ?? .calendarDay }
        set { dueRuleRaw = newValue.rawValue }
    }

    init(
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
