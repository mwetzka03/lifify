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
                        SettingsCategoryLabel(title: row.title, systemImage: row.symbol)
                    }
                }
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Einstellungen", "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
    }
}

@ViewBuilder
private func settingsDestination(_ symbol: String) -> some View {
    switch symbol {
    case "person.fill": UserSettingsView()
    case "eurosign": FinanceSettingsView()
    case "flame.fill": ChallengeSettingsView()
    case "heart.fill": HealthSettingsView()
    case "externaldrive.fill": DataManagementView()
    default: GeneralSettingsView()
    }
}

enum DeveloperCopy {
    static var toggle: String { L("Entwicklermodus", "Developer mode") }
}

/// Appearance, briefing, developer mode, then version last. The person lives under User.
enum GeneralSettingsOrder {
    static let sections = ["appearance", "briefing", "developer", "version"]
}

enum EditorCopy {
    static var moreSettings: String { L("Weitere Einstellungen", "More settings") }
    static let moreStartsClosed = true
}

private struct SettingsCategoryLabel: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    let title: String
    let systemImage: String

    var body: some View {
        let accent = AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.16), in: Circle())
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
    @AppStorage(AppPalette.storageKey) private var palette = AppPalette.green.rawValue
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @AppStorage(LififyNotifications.briefingEnabledKey) private var briefingEnabled = true
    @AppStorage(LififyNotifications.briefingRevisionKey) private var briefingRevision = 0

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
                let _ = developerDay
                return AppClock.simulatedDay
            },
            set: { AppClock.setSimulatedDay($0) }
        )
    }

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
                Picker(L("Stil", "Style"), selection: $palette) {
                    ForEach(AppPalette.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Text(L("Darstellung", "Appearance"))
            } footer: {
                Text(L(
                    "Alle Daten bleiben lokal auf diesem Gerät. Lifify verwendet kein Backend und benötigt kein Konto.",
                    "All data stays locally on this device. Lifify has no backend and needs no account."
                ))
            }
            .appGlassRow()
            Section {
                Toggle(L("Tägliches Briefing", "Daily briefing"), isOn: $briefingEnabled)
                BriefingWeekBoard(
                    master: briefingEnabled,
                    revision: briefingRevision,
                    time: briefingBinding
                ) {
                    briefingRevision += 1
                }
            } footer: {
                Text(L(
                    "Tippe einen Tag an, um das Briefing an diesem Wochentag ein- oder auszuschalten. Die Uhrzeit steht darunter. Die Mitteilung nennt Termine, fällige Challenges und ihre Coins, nahende Belohnungen, das nächste Gehalt und die Ausgaben dieses Tags. Abstinenz-Boni kommen zusätzlich und bleiben in der Mitteilungszentrale.",
                    "Tap a day to turn the briefing on or off for that weekday. The time sits underneath. The notification names events, due challenges and their coins, upcoming rewards, the next salary, and that day's expenses. Abstinence bonuses arrive as well and stay in Notification Center."
                ))
            }
            .appGlassRow()
            Section {
                Toggle(DeveloperCopy.toggle, isOn: developerModeBinding)
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
            .appGlassRow()
            Section {
                LabeledContent(L("Version", "Version"), value: AppChrome.version)
            }
            .appGlassRow()
        }
        .onChange(of: briefingEnabled) { Task { await DailyBriefingService.refresh(context: context) } }
        .onChange(of: briefingRevision) { Task { await DailyBriefingService.refresh(context: context) } }
        .appGlassList()
        .navigationTitle(L("Allgemein", "General"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UserSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("userName") private var userName = ""
    @AppStorage(UserProfile.birthKey) private var birthRaw = ""
    @State private var heightText = UserBody.heightText()
    @State private var weightText = UserBody.weightText()
    @State private var sex = UserBody.current().sex
    @State private var goal = UserBody.current().goal

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
                MeasureField(title: L("Zentimeter", "Centimetres"), text: $heightText)
                MeasureField(title: L("Kilogramm", "Kilograms"), text: $weightText)
                Picker(L("Geschlecht", "Sex"), selection: $sex) {
                    ForEach(BodySex.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("Ziel", "Goal"), selection: $goal) {
                    ForEach(BodyGoal.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text(birthRaw.isEmpty
                    ? L(
                        "Wähle dein Geburtsdatum. Das angezeigte Datum gilt erst, wenn du es änderst. Am Geburtstag gibt es einmal im Jahr 500 Coins. Größe, Gewicht und Ziel setzen das Kalorienziel. Den Schlüssel für die Erkennung trägst du unter Gesundheit ein.",
                        "Choose your date of birth. The date shown is saved once you change it. Your birthday pays 500 coins once each year. Height, weight, and the goal set the calorie target. The recognition key is entered under Health."
                    )
                    : L(
                        "Am Geburtstag gibt es einmal im Jahr 500 Coins. Größe, Gewicht und Ziel setzen das Kalorienziel. Ein Training an dem Tag hebt es. Den Schlüssel für die Erkennung trägst du unter Gesundheit ein.",
                        "Your birthday pays 500 coins once each year. Height, weight, and the goal set the calorie target. A workout that day raises it. The recognition key is entered under Health."
                    ))
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Nutzer", "User"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: heightText) { storeBody() }
        .onChange(of: weightText) { storeBody() }
        .onChange(of: sex) { storeBody() }
        .onChange(of: goal) { storeBody() }
    }

    private func storeBody() {
        UserBody.save(heightText: heightText, weightText: weightText, sex: sex, goal: goal)
    }
}

private struct BriefingWeekBoard: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    var master: Bool
    var revision: Int
    var time: (Int) -> Binding<Date>
    var changed: () -> Void
    @State private var editing: Int?

    var body: some View {
        let _ = revision
        let accent = AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(BriefingSchedule.weekdays, id: \.self) { weekday in
                    let on = LififyNotifications.dayEnabled(weekday)
                    Button {
                        LififyNotifications.setDayEnabled(weekday, !on)
                        changed()
                    } label: {
                        Text(BriefingWeek.abbreviation(weekday))
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(on && master ? accent : Color.secondary.opacity(0.16), in: Circle())
                            .foregroundStyle(on && master ? (scheme == .dark ? Color.black : Color.white) : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!master)
                }
            }
            HStack(spacing: 4) {
                ForEach(BriefingSchedule.weekdays, id: \.self) { weekday in
                    let on = master && LififyNotifications.dayEnabled(weekday)
                    Button {
                        editing = editing == weekday ? nil : weekday
                    } label: {
                        Text(timeLabel(weekday))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                editing == weekday ? accent.opacity(0.18) : Color.secondary.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!on)
                    .opacity(on ? 1 : 0.35)
                }
            }
            if let editing {
                DatePicker(
                    BriefingSchedule.weekdayLabel(editing),
                    selection: time(editing),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!master)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeLabel(_ weekday: Int) -> String {
        let clock = LififyNotifications.clock(for: weekday)
        return String(format: "%02d:%02d", clock.hour, clock.minute)
    }
}

private struct CheckDetailView: View {
    let result: LififyCheckResult

    var body: some View {
        let story = CheckStories.story(named: result.name)
        let measured = result.reading.isEmpty ? (result.detail ?? "") : result.reading
        let methods = CheckStories.methodsLine(result.name)
        let guide = CheckStories.readingGuide(result.name)
        List {
            Section {
                Text(story.summary)
                Text(CheckStories.filesLine(story.steps.map(\.source)))
                    .font(.subheadline)
                if let detail = result.detail, !result.passed {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(result.kind.label)
            }
            .appGlassRow()
            if !measured.isEmpty || !guide.isEmpty {
                Section {
                    if !guide.isEmpty {
                        Text(guide)
                    }
                    if !measured.isEmpty {
                        Text(CheckStories.actualLine(measured))
                            .foregroundStyle(result.passed ? Color.primary : Color.red)
                    }
                } header: {
                    Text(L("Gemessen", "Measured"))
                }
                .appGlassRow()
            }
            Section {
                ForEach(Array(story.steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CheckStories.stepTitle(index + 1))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(CheckStories.expectedLine(step.text))
                        if !methods.isEmpty {
                            Text(methods)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(CheckStories.sourceLine(step.source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(L("Schritte", "Steps"))
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(result.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperTestsView: View {
    @State private var results: [LififyCheckResult] = []
    @State private var expandedTopics: Set<String> = CheckResultList.startsCollapsed
        ? []
        : Set(LififyCheckTopic.allCases.map(\.rawValue))

    private func expanded(_ topic: LififyCheckTopic) -> Binding<Bool> {
        Binding(
            get: { expandedTopics.contains(topic.rawValue) },
            set: { isOn in
                if isOn {
                    expandedTopics.insert(topic.rawValue)
                } else {
                    expandedTopics.remove(topic.rawValue)
                }
            }
        )
    }

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
            .appGlassRow()
            ForEach(CheckResultList.groups(from: results)) { group in
                DisclosureGroup(isExpanded: expanded(group.topic)) {
                    ForEach(group.rows) { result in
                        NavigationLink {
                            CheckDetailView(result: result)
                        } label: {
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
                } label: {
                    HStack {
                        Text(group.topic.title)
                            .foregroundStyle(group.allPassed ? Color.primary : Color.red)
                        Spacer()
                        Text(group.summary)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .appGlassRow()
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
            .appGlassRow()
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
            .appGlassRow()
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
    @State private var pickedStreak = StreakSettings.thresholds[0]
    @State private var pickedMilestone: AbstinenceMilestone = .hour1
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
            .appGlassRow()
            Section {
                NavigationLink {
                    SystemCalendarSyncView()
                } label: {
                    Label(L("Kalender & Erinnerungen", "Calendar & Reminders"), systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .appGlassRow()
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
            .appGlassRow()
            Section {
                EvenBubbleRow(spacing: 8, lineSpacing: 8) {
                    ForEach(StreakSettings.thresholds, id: \.self) { threshold in
                        Button {
                            pickedStreak = threshold
                        } label: {
                            ChoiceBubble(title: "\(threshold)×", selected: pickedStreak == threshold)
                        }
                        .buttonStyle(.plain)
                    }
                }
                MultiplierRow(threshold: pickedStreak)
                    .id(pickedStreak)
            } header: {
                Text(L("Streak-Multiplikator", "Streak multiplier"))
            } footer: {
                Text(L(
                    "Ohne eigene Änderung gelten diese Standardwerte. Der Faktor gilt auf die Basis-Belohnung. Erreicht die Serie mehrere Stufen, zählt nur die höchste, nicht das Produkt.",
                    "These defaults apply until you change them. The factor applies to the base reward. When a streak reaches several steps, only the highest one counts, not the product."
                ))
            }
            .appGlassRow()
            Section {
                Picker(L("Schwierigkeit", "Difficulty"), selection: $bonusDifficulty) {
                    ForEach(AbstinenceDifficulty.allCases) { Text($0.label).tag($0) }
                }
                EvenBubbleRow(spacing: 8, lineSpacing: 8) {
                    ForEach(AbstinenceMilestone.allCases) { milestone in
                        Button {
                            pickedMilestone = milestone
                        } label: {
                            ChoiceBubble(title: milestone.label, selected: pickedMilestone == milestone)
                        }
                        .buttonStyle(.plain)
                    }
                }
                AbstinenceMultiplierRow(difficulty: bonusDifficulty, milestone: pickedMilestone)
                    .id("\(bonusDifficulty.rawValue)-\(pickedMilestone.rawValue)")
            } header: {
                Text(L("Abstinenz-Bonus", "Abstinence bonus"))
            } footer: {
                Text(L(
                    "Der Bonus ist dieser Faktor mal die Coins pro Tag. Leicht, mittel und schwer haben eigene Faktoren. Ohne Änderung gilt die Standardtabelle. Jede erreichte Stufe zahlt ihren Bonus.",
                    "The bonus is this factor times the coins per day. Easy, medium, and hard each have their own factors. The default table applies until you change it. Every reached step pays its bonus."
                ))
            }
            .appGlassRow()
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

private struct MeasureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HealthSettingsView: View {
    @AppStorage(RestChime.storageKey) private var restChimeID = 1005
    @State private var geminiKey = ""

    var body: some View {
        Form {
            Section {
                SecureField(L("Gemini-Schlüssel", "Gemini key"), text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L("Ernährung", "Nutrition"))
            } footer: {
                Text(L(
                    "Der Schlüssel bleibt auf diesem Gerät. Ein Essensfoto wird nur mit diesem Schlüssel an Gemini geschickt. Ohne Schlüssel bleibt das Foto hier.",
                    "The key stays on this device. A meal photo is sent to Gemini only with this key. Without a key the photo stays here."
                ))
            }
            .appGlassRow()
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
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Gesundheit", "Health"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            geminiKey = KeychainStore.string(account: MealRecognition.keyAccount) ?? ""
        }
        .onChange(of: geminiKey) {
            let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                KeychainStore.remove(account: MealRecognition.keyAccount)
            } else {
                KeychainStore.set(trimmed, account: MealRecognition.keyAccount)
            }
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
                            .appAccentForeground()
                    }
                }
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Klingelton", "Chime"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
