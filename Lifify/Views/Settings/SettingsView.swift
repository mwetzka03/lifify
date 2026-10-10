import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @State private var showingResetConfirmation = false
    @State private var resetError: String?

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
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label(L("Alle Daten löschen & App zurücksetzen", "Delete all data & reset app"), systemImage: "trash")
                }
            }
            Section(L("Über Lifify", "About Lifify")) {
                LabeledContent(L("Version", "Version"), value: "0.1.0")
                Text(L(
                    "Alle Daten bleiben lokal auf diesem Gerät. Lifify verwendet kein Backend und benötigt kein Konto.",
                    "All data stays locally on this device. Lifify has no backend and needs no account."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            L("Alle Daten löschen?", "Delete all data?"),
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            Button(L("Endgültig löschen", "Delete permanently"), role: .destructive) {
                do {
                    try BackupService.deleteAllData(from: context)
                    language = "de"
                    theme = AppTheme.system.rawValue
                } catch {
                    resetError = error.localizedDescription
                }
            }
        } message: {
            Text(L(
                "Konten, Buchungen, Budgets, Challenges, Shopdaten und alle weiteren lokalen Daten werden unwiderruflich gelöscht.",
                "Accounts, transactions, budgets, challenges, shop data, and all other local data will be permanently deleted."
            ))
        }
        .alert(L("Zurücksetzen fehlgeschlagen", "Reset failed"), isPresented: Binding(
            get: { resetError != nil },
            set: { if !$0 { resetError = nil } }
        )) {
            Button("OK") { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
    }
}
