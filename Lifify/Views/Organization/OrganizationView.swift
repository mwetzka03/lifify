import SwiftUI

struct OrganizationView: View {
    var body: some View {
        List {
            NavigationLink { ShoppingListView() } label: {
                Label(L("Einkaufszettel", "Shopping list"), systemImage: "cart")
            }
            NavigationLink { DebtsView() } label: {
                Label(L("Schulden", "Debts"), systemImage: "person.2")
            }
            NavigationLink { ExpenseGroupsView() } label: {
                Label(L("Ausgabengruppen", "Expense groups"), systemImage: "square.stack.3d.up")
            }
            NavigationLink { PortfolioView() } label: {
                Label(L("Depot", "Portfolio"), systemImage: "chart.line.uptrend.xyaxis")
            }
            NavigationLink { SavedArticlesView() } label: {
                Label(L("Gespeicherte Artikel", "Saved articles"), systemImage: "bookmark")
            }
        }
        .navigationTitle(L("Mehr", "More"))
    }
}
