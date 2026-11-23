import Foundation

/// The kinds of accounts.
public enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case checking
    case savings
    case savingsGroup
    case portfolio

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .checking: L("Girokonto", "Checking")
        case .savings: L("Spartopf", "Savings pot")
        case .savingsGroup: L("Oberspartopf", "Savings group")
        case .portfolio: L("Depot", "Portfolio")
        }
    }
}

/// The kinds of ledger bookings.
public enum LedgerKind: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case transfer
    case adjustment

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .income: L("Einnahme", "Income")
        case .expense: L("Ausgabe", "Expense")
        case .transfer: L("Umbuchung", "Transfer")
        case .adjustment: L("Saldo-Korrektur", "Balance adjustment")
        }
    }
}

/// What part of a booking is assigned to.
public enum SplitKind: String, Codable {
    case variableBudget
    case budgetPool
}

/// How often a planned amount repeats.
public enum Cadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly
    case yearly

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .weekly: L("Wöchentlich", "Weekly")
        case .biweekly: L("Alle zwei Wochen", "Biweekly")
        case .monthly: L("Monatlich", "Monthly")
        case .yearly: L("Jährlich", "Yearly")
        }
    }
}

/// Which day of the month a planned amount falls due.
public enum DueRule: String, Codable, CaseIterable, Identifiable {
    case calendarDay
    case firstBusinessDay
    case lastBusinessDay

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .calendarDay: L("Kalendertag", "Calendar day")
        case .firstBusinessDay: L("Erster Bankarbeitstag", "First banking day")
        case .lastBusinessDay: L("Letzter Bankarbeitstag", "Last banking day")
        }
    }
}

/// The length of a budget pool's period.
public enum BudgetPeriodMode: String, Codable, CaseIterable, Identifiable {
    case salaryPeriod
    case calendarYear

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .salaryPeriod: L("Gehaltszeitraum", "Salary period")
        case .calendarYear: L("Kalenderjahr", "Calendar year")
        }
    }
}

/// Who owes whom in a debt entry.
public enum DebtDirection: String, Codable, CaseIterable, Identifiable {
    case owedToMe
    case iOwe

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .owedToMe: L("Bekomme ich", "Owed to me")
        case .iOwe: L("Schulde ich", "I owe")
        }
    }
}

/// The light or dark appearance.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: L("System", "System")
        case .light: L("Hell", "Light")
        case .dark: L("Dunkel", "Dark")
        }
    }
}
