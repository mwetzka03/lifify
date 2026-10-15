import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @AppStorage("onboardingStep") private var onboardingStep = 0
    @AppStorage(WorkoutAPIKey.storageKey) private var workoutAPIKey = ""
    @AppStorage(RestChime.storageKey) private var restChimeID = 1005
    @AppStorage(TradeFeePreference.storageKey) private var defaultTradeFeeCents = TradeFeePreference.defaultCents
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
                SecureField(L("Workout-API-Schlüssel", "Workout API key"), text: $workoutAPIKey)
                Text(L(
                    "Der Klingelton beendet die Satzpause. Der Schlüssel lädt Übungen und Bilder und bleibt auf diesem Gerät.",
                    "The chime ends a rest period. The key loads exercises and images and stays on this device."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Training", "Training"))
            }
            Section {
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
                    "Standard für Nachkauf und Verkauf ist 1 €. Die Gebühr gilt einmal pro Buchung, nicht pro Stück.",
                    "The default for additional buys and sales is €1. The fee applies once per booking, not per share."
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
