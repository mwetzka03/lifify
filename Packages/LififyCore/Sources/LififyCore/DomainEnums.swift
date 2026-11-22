import Foundation

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

public enum SplitKind: String, Codable {
    case variableBudget
    case budgetPool
}

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
