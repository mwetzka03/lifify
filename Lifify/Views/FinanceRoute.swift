import SwiftUI

enum FinanceRoute: Hashable, Codable {
    case income
    case expenses
    case incomeForecasts
    case transferForecasts
    case fixedCosts
    case variableCosts
    case shopping
    case transactions
    case budgetPools
    case debts
    case expenseGroups
    case portfolio
    case savingsPlans
    case portfolioShares
}

struct FinanceMoreLink: Identifiable, Equatable {
    var title: String
    var symbol: String
    var route: FinanceRoute
    var id: FinanceRoute { route }
}

/// Titles and type for Weitere Bereiche. The row type matches the finance tiles.
enum FinanceMoreDirectory {
    static let title = L("Weitere Bereiche", "More")
    static let sectionFontName = "subheadline"
    static let rowFontName = "subheadline"
    static let chevronFontName = "footnote"
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 12

    static var rows: [FinanceMoreLink] {
        [
            FinanceMoreLink(title: L("Budgetpools", "Budget pools"), symbol: "tray.full", route: .budgetPools),
            FinanceMoreLink(title: L("Ausgabengruppen", "Expense groups"), symbol: "square.stack.3d.up", route: .expenseGroups),
            FinanceMoreLink(title: L("Schulden", "Debts"), symbol: "person.2", route: .debts)
        ]
    }

    static func font(_ name: String) -> Font {
        switch name {
        case "footnote": .footnote
        default: .subheadline
        }
    }
}

enum FinanceTileCopy {
    static var shopping: String { L("Einkaufszettel", "Shopping list") }
    static var applied: String { L("Angewendet", "Applied") }
    static var planned: String { L("Geplant", "Planned") }
}

struct FinanceRouteScreen: View {
    let route: FinanceRoute

    var body: some View {
        switch route {
        case .income:
            FilteredLedgerView(kind: .income)
        case .expenses:
            FilteredLedgerView(kind: .expense)
        case .incomeForecasts:
            FilteredLedgerView(kind: .income)
        case .transferForecasts:
            TransferForecastsView()
        case .fixedCosts:
            FixedCostsView()
        case .variableCosts:
            VariableBudgetsView()
        case .shopping:
            ShoppingListView()
        case .transactions:
            TransactionsView()
        case .budgetPools:
            BudgetPoolsView()
        case .debts:
            DebtsView()
        case .expenseGroups:
            ExpenseGroupsView()
        case .portfolio:
            PortfolioView()
        case .savingsPlans:
            SavingsPlansView()
        case .portfolioShares:
            PortfolioShareChartView()
        }
    }
}
