import LififyCore
import LififyFinance
import SwiftUI

/// The switches of the Face ID lock. A change that weakens the lock needs the device owner.
struct FinanceLockSection: View {
    @Environment(FinanceLock.self) private var lock
    @AppStorage(FinanceLockSettings.enabledKey) private var isEnabled = true
    @AppStorage(FinanceLockSettings.widgetValuesKey) private var showsWidgetValues = false

    var body: some View {
        Section {
            Toggle(L("Finanzen mit Face ID sperren", "Lock Finance with Face ID"), isOn: lockBinding)
            if isEnabled {
                Toggle(L("Finanzwerte in Widgets zeigen", "Show finance values in widgets"), isOn: widgetBinding)
            }
        } header: {
            Text(L("Sperre", "Lock"))
        } footer: {
            Text(L(
                "Der Tab Finanzen wird mit Face ID oder dem Gerätecode entsperrt und bleibt offen, bis die App in den Hintergrund geht.",
                "The Finance tab unlocks with Face ID or the device passcode and stays open until the app goes to the background."
            ))
        }
        .appGlassRow()
    }

    /// Turning the lock off needs confirmation. Turning it on does not.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { wanted in
                guard !wanted else {
                    isEnabled = true
                    return
                }
                Task { if await lock.confirmWeakening() { isEnabled = false } }
            }
        )
    }

    /// Showing amounts in widgets needs confirmation. Hiding them does not.
    private var widgetBinding: Binding<Bool> {
        Binding(
            get: { showsWidgetValues },
            set: { wanted in
                guard wanted else {
                    showsWidgetValues = false
                    return
                }
                Task { if await lock.confirmWeakening() { showsWidgetValues = true } }
            }
        )
    }
}
