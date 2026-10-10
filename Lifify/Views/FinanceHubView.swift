import SwiftUI

struct FinanceHubView: View {
    var body: some View {
        List {
            NavigationLink {
                DashboardView()
            } label: {
                Label(L("Finanzübersicht", "Financial overview"), systemImage: "chart.pie")
            }
            NavigationLink {
                TransactionsView()
            } label: {
                Label(L("Buchungen", "Transactions"), systemImage: "list.bullet.rectangle")
            }
            NavigationLink {
                PlanningView()
            } label: {
                Label(L("Budgets und Planung", "Budgets and planning"), systemImage: "calendar")
            }
            NavigationLink {
                OrganizationView()
            } label: {
                Label(L("Einkäufe, Schulden und Depot", "Shopping, debts and portfolio"), systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle(L("Finanzen", "Finance"))
    }
}
