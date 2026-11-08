import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section {
                ForEach(SettingsDirectory.rows()) { row in
                    NavigationLink {
                        settingsDestination(row.symbol)
                    } label: {
                        SettingsCategoryLabel(title: row.title, systemImage: row.symbol, color: settingsColor(row.symbol))
                    }
                }
            }
        }
        .appGlassList()
        .navigationTitle(L("Einstellungen", "Settings"))
    }
}

@ViewBuilder
private func settingsDestination(_ symbol: String) -> some View {
    switch symbol {
    case "eurosign": FinanceSettingsView()
    case "flame.fill": ChallengeSettingsView()
    case "heart.fill": HealthSettingsView()
    case "externaldrive.fill": DataManagementView()
    default: GeneralSettingsView()
    }
}

private func settingsColor(_ symbol: String) -> Color {
    switch symbol {
    case "eurosign": Color(red: 0.18, green: 0.72, blue: 0.38)
    case "flame.fill": .orange
    case "heart.fill": .red
    case "externaldrive.fill": Color(red: 0.35, green: 0.34, blue: 0.84)
    default: Color(white: 0.56)
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
    @Environment(\.modelContext) private var context
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @AppStorage("userName") private var userName = ""
    @AppStorage(UserProfile.birthKey) private var birthRaw = ""
    @AppStorage(LififyNotifications.briefingEnabledKey) private var briefingEnabled = true
    @AppStorage(LififyNotifications.briefingRevisionKey) private var briefingRevision = 0

    private var birthSelection: Binding<Date> {
        Binding(
            get: { UserProfile.birthDate() ?? UserProfile.suggestedDate() },
            set: { newValue in
                UserProfile.setBirthDate(newValue)
                birthRaw = UserProfile.birthRaw()
                BirthdayBonusService.settle(context: context)
            }
        )
    }

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { developerMode },
            set: { enabled in
                developerMode = enabled
                AppClock.resetSimulatedDay()
            }
        )
    }

    private func briefingBinding(_ weekday: Int) -> Binding<Date> {
        Binding(
            get: {
                let _ = briefingRevision
                let clock = LififyNotifications.clock(for: weekday)
                var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                parts.hour = clock.hour
                parts.minute = clock.minute
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                LififyNotifications.setClock(weekday: weekday, hour: parts.hour ?? 8, minute: parts.minute ?? 0)
                briefingRevision += 1
            }
        )
    }

    private var simulatedDay: Binding<Date> {
        Binding(
            get: {
                developerDay > 0 ? Date(timeIntervalSince1970: developerDay) : Calendar.current.startOfDay(for: Date())
            },
            set: { developerDay = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Name", "Name"), text: $userName)
                DatePicker(
                    L("Geburtsdatum", "Date of birth"),
                    selection: birthSelection,
                    in: ...Date(),
                    displayedComponents: .date
                )
            } header: {
                Text(L("Profil", "Profile"))
            } footer: {
                Text(birthRaw.isEmpty
                    ? L(
                        "Wähle dein Geburtsdatum. Das angezeigte Datum gilt erst, wenn du es änderst. Am Geburtstag gibt es einmal im Jahr 500 Coins. Der 29. Februar fällt in einem Jahr ohne diesen Tag auf den 28. Februar.",
                        "Choose your date of birth. The date shown is saved once you change it. Your birthday pays 500 coins once each year. In a year without 29 February, that birthday falls on 28 February."
                    )
                    : L(
                        "Am Geburtstag gibt es einmal im Jahr 500 Coins. Der 29. Februar fällt in einem Jahr ohne diesen Tag auf den 28. Februar.",
                        "Your birthday pays 500 coins once each year. In a year without 29 February, that birthday falls on 28 February."
                    ))
            }
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
                Toggle(L("Entwicklermodus", "Developer mode"), isOn: developerModeBinding)
                if developerMode {
                    DatePicker(L("Aktueller Tag", "Current day"), selection: simulatedDay, displayedComponents: .date)
                    NavigationLink {
                        DeveloperTestsView()
                    } label: {
                        Label(L("Tests ausführen", "Run tests"), systemImage: "checkmark.seal")
                    }
                }
            } footer: {
                Text(L(
                    "Der Tag gilt für Home, Challenges und den Kalender. Finanzen bleiben beim echten Datum. Beim Start der App und beim Ein- oder Ausschalten springt der Tag auf heute zurück.",
                    "The day applies to Home, challenges, and the calendar. Finance stays on the real date. Launching the app or switching the mode puts the day back on today."
                ))
            }
            Section {
                Toggle(L("Tägliches Briefing", "Daily briefing"), isOn: $briefingEnabled)
                ForEach(BriefingSchedule.weekdays, id: \.self) { weekday in
                    DatePicker(
                        BriefingSchedule.weekdayLabel(weekday),
                        selection: briefingBinding(weekday),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!briefingEnabled)
                }
            } footer: {
                Text(L(
                    "Eine Mitteilung am Tag, mit einer eigenen Uhrzeit von Montag bis Sonntag. Sie nennt Termine, fällige Challenges und ihre Coins, nahende Belohnungen, das nächste Gehalt und die Ausgaben dieses Tags. Abstinenz-Boni kommen zusätzlich und bleiben in der Mitteilungszentrale.",
                    "One notification a day, with its own time from Monday through Sunday. It names events, due challenges and their coins, upcoming rewards, the next salary, and that day's expenses. Abstinence bonuses arrive as well and stay in Notification Center."
                ))
            }
            Section {
                LabeledContent(L("Version", "Version"), value: AppChrome.version)
            }
        }
        .onChange(of: briefingEnabled) { Task { await DailyBriefingService.refresh(context: context) } }
        .onChange(of: briefingRevision) { Task { await DailyBriefingService.refresh(context: context) } }
        .appGlassList()
        .navigationTitle(L("Allgemein", "General"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperTestsView: View {
    @State private var results: [LififyCheckResult] = []

    var body: some View {
        List {
            Section {
                let passed = results.filter(\.passed).count
                LabeledContent(L("Bestanden", "Passed"), value: "\(passed)/\(results.count)")
            } footer: {
                Text(L(
                    "Dieselben Prüfungen laufen in Xcode als LififyChecksTests. Sie schreiben keine Daten.",
                    "The same checks run in Xcode as LififyChecksTests. They do not write any data."
                ))
            }
            ForEach(LififyCheckTopic.allCases, id: \.self) { topic in
                let rows = results.filter { $0.topic == topic }
                if !rows.isEmpty {
                    Section(topic.title) {
                        ForEach(rows) { result in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.kind.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(result.name)
                                    if let detail = result.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .appGlassList()
        .navigationTitle(L("Tests", "Tests"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Nochmal", "Again")) { results = LififyChecks.run() }
            }
        }
        .onAppear { results = LififyChecks.run() }
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
        .appGlassList()
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
    @AppStorage(StreakSettings.freezeFactorKey) private var freezeFactor = 10
    @AppStorage(ChallengeCategoryStore.revisionKey) private var categoryRevision = 0
    @State private var factorText = ""
    @State private var bonusDifficulty: AbstinenceDifficulty = .medium
    @State private var editedCategory: CustomChallengeCategory?
    @State private var showingNewCategory = false

    var body: some View {
        let _ = categoryRevision
        Form {
            Section {
                ForEach(ChallengeCategoryStore.all()) { category in
                    Button {
                        editedCategory = category
                    } label: {
                        HStack {
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if category.separate {
                                Text(L("Separat", "Separate"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            ChallengeCategoryStore.remove(category.id)
                        } label: {
                            Label(L("Löschen", "Delete"), systemImage: "trash")
                        }
                    }
                }
                Button(L("Kategorie hinzufügen", "Add category")) { showingNewCategory = true }
            } header: {
                Text(L("Kategorien", "Categories"))
            } footer: {
                Text(L(
                    "Sport, Abstinenz und Sonstiges gibt es immer. Eine eigene Kategorie kann separat eine Überschrift in der aktiven Liste bekommen. Sonst liegt sie bei den übrigen.",
                    "Sport, abstinence, and other always exist. A custom category can have its own heading in the active list. Otherwise it stays with the rest."
                ))
            }
            Section {
                NavigationLink {
                    SystemCalendarSyncView()
                } label: {
                    Label(L("Kalender & Erinnerungen", "Calendar & Reminders"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Section {
                TextField(L("Faktor", "Factor"), text: $factorText)
                    .keyboardType(.numberPad)
            } header: {
                Text(L("Streak-Freeze", "Streak freeze"))
            } footer: {
                Text(L(
                    "Ein zusätzlicher Freeze kostet diesen ganzzahligen Faktor mal die Basis-Belohnung. Standard ist 10.",
                    "An extra freeze costs this whole-number factor times the base reward. The default is 10."
                ))
            }
            Section {
                ForEach(StreakSettings.thresholds, id: \.self) { threshold in
                    MultiplierRow(threshold: threshold)
                }
            } header: {
                Text(L("Streak-Multiplikator", "Streak multiplier"))
            } footer: {
                Text(L(
                    "Ohne eigene Änderung gelten diese Standardwerte. Der Faktor gilt auf die Basis-Belohnung. Erreicht die Serie mehrere Stufen, zählt nur die höchste, nicht das Produkt.",
                    "These defaults apply until you change them. The factor applies to the base reward. When a streak reaches several steps, only the highest one counts, not the product."
                ))
            }
            Section {
                Picker(L("Schwierigkeit", "Difficulty"), selection: $bonusDifficulty) {
                    ForEach(AbstinenceDifficulty.allCases) { Text($0.label).tag($0) }
                }
                ForEach(AbstinenceMilestone.allCases) { milestone in
                    AbstinenceMultiplierRow(difficulty: bonusDifficulty, milestone: milestone)
                        .id("\(bonusDifficulty.rawValue)-\(milestone.rawValue)")
                }
            } header: {
                Text(L("Abstinenz-Bonus", "Abstinence bonus"))
            } footer: {
                Text(L(
                    "Der Bonus ist dieser Faktor mal die Coins pro Tag. Leicht, mittel und schwer haben eigene Faktoren. Ohne Änderung gilt die Standardtabelle. Jede erreichte Stufe zahlt ihren Bonus.",
                    "The bonus is this factor times the coins per day. Easy, medium, and hard each have their own factors. The default table applies until you change it. Every reached step pays its bonus."
                ))
            }
        }
        .appGlassList()
        .navigationTitle(L("Herausforderung", "Challenges"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if factorText.isEmpty {
                factorText = String(max(freezeFactor, 1))
            }
        }
        .onChange(of: factorText) {
            if factorText.isEmpty { return }
            guard let value = StreakSettings.wholeFactor(from: factorText) else {
                factorText = String(max(freezeFactor, 1))
                return
            }
            freezeFactor = value
        }
        .sheet(isPresented: $showingNewCategory) {
            CustomCategoryEditor(existing: nil) { _ in }
        }
        .sheet(item: $editedCategory) { category in
            CustomCategoryEditor(existing: category) { _ in }
        }
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

private struct AbstinenceMultiplierRow: View {
    let difficulty: AbstinenceDifficulty
    let milestone: AbstinenceMilestone
    @State private var text: String

    init(difficulty: AbstinenceDifficulty, milestone: AbstinenceMilestone) {
        self.difficulty = difficulty
        self.milestone = milestone
        _text = State(initialValue: AbstinenceSettings.editString(difficulty: difficulty, milestone: milestone))
    }

    var body: some View {
        HStack {
            Text(milestone.label)
            Spacer()
            TextField("1", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
        }
        .onChange(of: text) {
            guard let value = StreakSettings.parseMultiplier(text) else { return }
            AbstinenceSettings.setMultiplier(value, difficulty: difficulty, milestone: milestone)
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
        .appGlassList()
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
        .appGlassList()
        .navigationTitle(L("Klingelton", "Chime"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
