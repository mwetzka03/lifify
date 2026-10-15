import SwiftUI

enum FinanceRoute: Hashable, Codable {
    case income
    case expenses
    case incomeForecasts
    case fixedCosts
    case variableCosts
    case shopping
    case transactions
    case budgetPools
    case debts
    case expenseGroups
    case portfolio
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
        }
    }
}
