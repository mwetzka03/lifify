import SwiftData
import SwiftUI

@main
struct LififyApp: App {
    private let container: ModelContainer = {
        let schema = Schema([
            Account.self,
            LedgerEntry.self,
            TransactionSplit.self,
            FixedCost.self,
            VariableBudget.self,
            BudgetPool.self,
            IncomeForecast.self,
            ShoppingItem.self,
            DebtEntry.self,
            ExpenseGroup.self,
            ExpenseGroupLine.self,
            PortfolioHolding.self,
            SavedArticle.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Lifify data store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
