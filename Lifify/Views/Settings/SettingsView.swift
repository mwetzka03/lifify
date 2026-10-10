import SwiftUI

struct SettingsView: View {
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue

    var body: some View {
        Form {
            Section(L("Darstellung", "Appearance")) {
                Picker(L("Sprache", "Language"), selection: $language) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                Picker(L("Erscheinungsbild", "Appearance"), selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section(L("Daten", "Data")) {
                NavigationLink {
                    AccountsSettingsView()
                } label: {
                    Label(L("Konten", "Accounts"), systemImage: "building.columns")
                }
                NavigationLink {
                    DataManagementView()
                } label: {
                    Label(L("Import und Sicherung", "Import and backup"), systemImage: "externaldrive")
                }
                NavigationLink {
                    SystemCalendarSyncView()
                } label: {
                    Label(L("Kalender & Erinnerungen", "Calendar & Reminders"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Section(L("Über Lifify", "About Lifify")) {
                LabeledContent(L("Version", "Version"), value: "1.0.0")
                Text(L(
                    "Alle Daten bleiben lokal auf diesem Gerät. Lifify verwendet kein Backend und benötigt kein Konto.",
                    "All data stays locally on this device. Lifify has no backend and needs no account."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}
