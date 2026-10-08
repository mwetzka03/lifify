import SwiftUI

struct PlanningView: View {
    var body: some View {
        List {
            NavigationLink {
                FixedCostsView()
            } label: {
                Label(L("Fixkosten", "Fixed costs"), systemImage: "repeat")
            }
            NavigationLink {
                VariableBudgetsView()
            } label: {
                Label(L("Variable Monatsbudgets", "Variable monthly budgets"), systemImage: "gauge.with.dots.needle.67percent")
            }
            NavigationLink {
                BudgetPoolsView()
            } label: {
                Label(L("Budgetpools", "Budget pools"), systemImage: "tray.full")
            }
            NavigationLink {
                IncomeForecastsView()
            } label: {
                Label(L("Einnahmeprognosen", "Income forecasts"), systemImage: "calendar.badge.plus")
            }
        }
        .navigationTitle(L("Planung", "Planning"))
    }
}
