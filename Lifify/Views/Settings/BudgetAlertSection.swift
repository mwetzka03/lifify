import LififyCore
import LififyFinance
import SwiftUI

/// The switches and thresholds of the budget warnings.
struct BudgetAlertSection: View {
    @AppStorage(BudgetAlertSettings.enabledKey) private var enabled = true
    @AppStorage(BudgetAlertSettings.budgetsKey) private var budgets = true
    @AppStorage(BudgetAlertSettings.dailyKey) private var daily = true
    @AppStorage(BudgetAlertSettings.firstKey) private var first = BudgetAlertSettings.defaultFirst
    @AppStorage(BudgetAlertSettings.secondKey) private var second = BudgetAlertSettings.defaultSecond

    var body: some View {
        Section {
            Toggle(L("Budget-Warnungen", "Budget warnings"), isOn: $enabled)
            if enabled {
                Toggle(L("Variable Kosten und Pools", "Variable costs and pools"), isOn: $budgets)
                if budgets {
                    Stepper(value: $first, in: 50...95, step: 5) {
                        LabeledContent(L("Erste Warnung", "First warning"), value: "\(first) %")
                    }
                    Stepper(value: $second, in: 100...150, step: 5) {
                        LabeledContent(L("Zweite Warnung", "Second warning"), value: "\(second) %")
                    }
                }
                Toggle(L("Tagesbudget überschritten", "Daily budget exceeded"), isOn: $daily)
            }
        } footer: {
            Text(L(
                "Pro Schwelle und Zeitraum kommt eine Mitteilung. Nach einem Import werden mehrere Warnungen gebündelt.",
                "Each threshold notifies once per period. After an import, several warnings arrive as one."
            ))
        }
        .appGlassRow()
    }
}
