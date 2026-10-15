import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @AppStorage("onboardingStep") private var onboardingStep = 0
    @AppStorage(RestChime.storageKey) private var restChimeID = 1005
    @AppStorage(TradeFeePreference.storageKey) private var defaultTradeFeeCents = TradeFeePreference.defaultCents
    @AppStorage(TradeAccountPreference.storageKey) private var defaultCheckingAccountID = ""
    @EnvironmentObject private var workouts: WorkoutStore
    @State private var feeText = ""
    @State private var destructiveAction: DestructiveAction?
    @State private var resetError: String?

    var body: some View {
        Form {
            Section(L("Über Lifify", "About Lifify")) {
                LabeledContent(L("Version", "Version"), value: "0.1.0")
                Text(L(
                    "Alle Daten bleiben lokal auf diesem Gerät. Lifify verwendet kein Backend und benötigt kein Konto.",
                    "All data stays locally on this device. Lifify has no backend and needs no account."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Section(L("Darstellung", "Appearance")) {
                Picker(L("Sprache", "Language"), selection: $language) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                Picker(L("Erscheinungsbild", "Appearance"), selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                NavigationLink {
                    RestChimePicker(selection: $restChimeID)
                } label: {
                    LabeledContent(L("Klingelton", "Chime"), value: RestChime.tones.first { $0.id == restChimeID }?.name ?? RestChime.selectedName)
                }
                Text(L(
                    "Der Klingelton beendet die Satzpause. Übungen kommen aus der lokalen Datenbank.",
                    "The chime ends a rest period. Exercises come from the local database."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Training", "Training"))
            }
            Section {
                Picker(L("Standard-Girokonto", "Default checking account"), selection: $defaultCheckingAccountID) {
                    Text(L("Erstes Girokonto", "First checking account")).tag("")
                    ForEach(accounts.filter { $0.kind == .checking }) { account in
                        Text(account.name).tag(account.id.uuidString)
                    }
                }
                HStack {
                    Text(L("Gebühr pro Buchung", "Fee per booking"))
                    Spacer()
                    TextField("1,00", text: $feeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text("€")
                        .foregroundStyle(.secondary)
                }
                Text(L(
                    "Das Girokonto wird beim Kauf und Verkauf vorausgewählt. Die Gebühr ist abschaltbar und gilt einmal pro Buchung, nicht pro Stück.",
                    "The checking account is preselected for buys and sales. The fee can be turned off and applies once per booking, not per share."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Depot", "Portfolio"))
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
            Section {
                Button(role: .destructive) {
                    destructiveAction = .deleteData
                } label: {
                    Label(L("Alle Daten löschen", "Delete all data"), systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
                Button(role: .destructive) {
                    destructiveAction = .resetApp
                } label: {
                    Label(L("App zurücksetzen", "Reset app"), systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
            }
        }
        .confirmationDialog(
            destructiveAction?.title ?? "",
            isPresented: Binding(
                get: { destructiveAction != nil },
                set: { if !$0 { destructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            Button(L("Endgültig löschen", "Delete permanently"), role: .destructive) {
                do {
                    switch destructiveAction {
                    case .deleteData:
                        try BackupService.deleteUserData(from: context)
                    case .resetApp:
                        try BackupService.resetApp(from: context)
                        workouts.reset()
                        ExerciseImageStore.removeAll()
                        defaultTradeFeeCents = TradeFeePreference.defaultCents
                        feeText = TradeFeePreference.editString(cents: TradeFeePreference.defaultCents)
                        defaultCheckingAccountID = ""
                        language = "de"
                        theme = AppTheme.system.rawValue
                        userName = ""
                        dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
                        onboardingStep = 0
                        onboardingInProgress = false
                        hasCompletedOnboarding = false
                    case nil:
                        break
                    }
                    destructiveAction = nil
                } catch {
                    resetError = error.localizedDescription
                }
            }
        } message: {
            Text(destructiveAction?.message ?? "")
        }
        .onAppear {
            if feeText.isEmpty {
                feeText = TradeFeePreference.editString(cents: defaultTradeFeeCents)
            }
        }
        .onChange(of: feeText) {
            guard let cents = Money.cents(from: feeText), cents >= 0 else { return }
            defaultTradeFeeCents = cents
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

private enum DestructiveAction {
    case deleteData
    case resetApp

    var title: String {
        switch self {
        case .deleteData: L("Alle Daten löschen?", "Delete all data?")
        case .resetApp: L("App vollständig zurücksetzen?", "Reset the entire app?")
        }
    }

    var message: String {
        switch self {
        case .deleteData:
            L(
                "Buchungen, Budgets, Challenges und weitere Inhalte werden gelöscht. Deine Konten und App-Einstellungen bleiben erhalten.",
                "Transactions, budgets, challenges, and other content will be deleted. Accounts and app settings remain."
            )
        case .resetApp:
            L(
                "Auch Konten, Trainingsdaten und Einstellungen werden gelöscht. Danach beginnt die Ersteinrichtung erneut.",
                "Accounts, workout data, and settings will also be deleted. Initial setup starts again afterward."
            )
        }
    }
}

private struct RestChimePicker: View {
    @Binding var selection: Int

    var body: some View {
        List(RestChime.tones) { tone in
            Button {
                selection = tone.id
                RestChime.preview(tone.id)
            } label: {
                HStack {
                    Text(tone.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if tone.id == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .navigationTitle(L("Klingelton", "Chime"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
