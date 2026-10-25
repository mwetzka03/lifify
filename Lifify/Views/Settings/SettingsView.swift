import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    SettingsCategoryLabel(title: L("Allgemein", "General"), systemImage: "gearshape.fill", color: Color(white: 0.56))
                }
                NavigationLink {
                    FinanceSettingsView()
                } label: {
                    SettingsCategoryLabel(title: L("Finanzen", "Finance"), systemImage: "eurosign", color: Color(red: 0.18, green: 0.72, blue: 0.38))
                }
                NavigationLink {
                    ChallengeSettingsView()
                } label: {
                    SettingsCategoryLabel(title: L("Herausforderung", "Challenges"), systemImage: "flame.fill", color: .orange)
                }
                NavigationLink {
                    HealthSettingsView()
                } label: {
                    SettingsCategoryLabel(title: L("Gesundheit", "Health"), systemImage: "heart.fill", color: .red)
                }
                NavigationLink {
                    DataManagementView()
                } label: {
                    SettingsCategoryLabel(title: L("Daten", "Data"), systemImage: "externaldrive.fill", color: Color(red: 0.35, green: 0.34, blue: 0.84))
                }
            }
        }
        .navigationTitle(L("Einstellungen", "Settings"))
    }
}

private struct SettingsCategoryLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue

    var body: some View {
        Form {
            Section {
                Picker(L("Sprache", "Language"), selection: $language) {
                    Text("Deutsch").tag("de")
                    Text("English").tag("en")
                }
                Picker(L("Erscheinungsbild", "Appearance"), selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Text(L("Darstellung", "Appearance"))
            } footer: {
                Text(L(
                    "Alle Daten bleiben lokal auf diesem Gerät. Lifify verwendet kein Backend und benötigt kein Konto.",
                    "All data stays locally on this device. Lifify has no backend and needs no account."
                ))
            }
            Section {
                LabeledContent(L("Version", "Version"), value: "0.3.0")
            }
        }
        .navigationTitle(L("Allgemein", "General"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FinanceSettingsView: View {
    @Query(sort: \Account.name) private var accounts: [Account]
    @AppStorage(TradeFeePreference.storageKey) private var defaultTradeFeeCents = TradeFeePreference.defaultCents
    @AppStorage(TradeAccountPreference.storageKey) private var defaultCheckingAccountID = ""
    @State private var feeText = ""

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AccountsSettingsView()
                } label: {
                    Label(L("Konten", "Accounts"), systemImage: "building.columns")
                }
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
            } header: {
                Text(L("Depot", "Portfolio"))
            } footer: {
                Text(L(
                    "Das Girokonto wird beim Kauf und Verkauf vorausgewählt. Die Gebühr ist abschaltbar und gilt einmal pro Buchung, nicht pro Stück.",
                    "The checking account is preselected for buys and sales. The fee can be turned off and applies once per booking, not per share."
                ))
            }
        }
        .navigationTitle(L("Finanzen", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if feeText.isEmpty {
                feeText = TradeFeePreference.editString(cents: defaultTradeFeeCents)
            }
        }
        .onChange(of: feeText) {
            guard let cents = Money.cents(from: feeText), cents >= 0 else { return }
            defaultTradeFeeCents = cents
        }
    }
}

private struct ChallengeSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    SystemCalendarSyncView()
                } label: {
                    Label(L("Kalender & Erinnerungen", "Calendar & Reminders"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Section {
                ForEach(StreakSettings.thresholds, id: \.self) { threshold in
                    MultiplierRow(threshold: threshold)
                }
            } header: {
                Text(L("Streak-Multiplikator", "Streak multiplier"))
            } footer: {
                Text(L(
                    "Der Faktor gilt auf die Basis-Belohnung. Erreicht die Serie mehrere Stufen, zählt nur die höchste, nicht das Produkt. Die Quote folgt der Frequenz, zum Beispiel dreimal pro Woche oder einmal im Monat.",
                    "The factor applies to the base reward. When a streak reaches several steps, only the highest one counts, not the product. The quota follows the frequency, for example three times a week or once a month."
                ))
            }
        }
        .navigationTitle(L("Herausforderung", "Challenges"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MultiplierRow: View {
    let threshold: Int
    @State private var text: String

    init(threshold: Int) {
        self.threshold = threshold
        _text = State(initialValue: StreakSettings.editString(for: threshold))
    }

    var body: some View {
        HStack {
            Text("\(L("Nach", "After")) \(threshold)×")
            Spacer()
            TextField("1", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
        }
        .onChange(of: text) {
            guard let value = StreakSettings.parseMultiplier(text) else { return }
            StreakSettings.setMultiplier(value, for: threshold)
        }
    }
}

private struct HealthSettingsView: View {
    @AppStorage(RestChime.storageKey) private var restChimeID = 1005

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    RestChimePicker(selection: $restChimeID)
                } label: {
                    LabeledContent(L("Klingelton", "Chime"), value: RestChime.tones.first { $0.id == restChimeID }?.name ?? RestChime.selectedName)
                }
            } header: {
                Text(L("Training", "Training"))
            } footer: {
                Text(L(
                    "Der Klingelton beendet die Satzpause. Übungen kommen aus der lokalen Datenbank.",
                    "The chime ends a rest period. Exercises come from the local database."
                ))
            }
        }
        .navigationTitle(L("Gesundheit", "Health"))
        .navigationBarTitleDisplayMode(.inline)
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
