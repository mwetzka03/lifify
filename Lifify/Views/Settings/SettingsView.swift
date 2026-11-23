import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The settings list.
struct SettingsView: View {
    @AppStorage("userName") private var userName = ""

    var body: some View {
        let rows = SettingsDirectory.rows()
        List {
            if let profile = rows.first(where: { $0.symbol == "person.fill" }) {
                Section {
                    NavigationLink {
                        UserSettingsView()
                    } label: {
                        profileRow(profile.title)
                    }
                }
                .appGlassRow()
            }
            Section {
                ForEach(rows.filter { $0.symbol != "person.fill" }) { row in
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

    /// The profile row.
    private func profileRow(_ subtitle: String) -> some View {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 14) {
            ProfileAvatar(side: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(trimmed.isEmpty ? L("Name", "Name") : trimmed)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

/// The screen of a settings entry.
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

/// Texts of the developer mode.
enum DeveloperCopy {
    static var toggle: String { L("Entwicklermodus", "Developer mode") }
}

/// Appearance, briefing, developer mode, then version last. The person lives under User.
enum GeneralSettingsOrder {
    static let sections = ["appearance", "briefing", "developer", "version"]
}

/// Texts of the editors.
enum EditorCopy {
    static var moreSettings: String { L("Weitere Einstellungen", "More settings") }
    static let moreStartsClosed = true
}

/// One settings entry.
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

/// General settings.
private struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage(AppPalette.storageKey) private var palette = AppPalette.green.rawValue
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(TradeRepublicSample.revisionKey) private var tradeRepublicSampleRevision = 0
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @AppStorage(LififyNotifications.briefingEnabledKey) private var briefingEnabled = true
    @AppStorage(LififyNotifications.briefingRevisionKey) private var briefingRevision = 0

    private var developerModeBinding: Binding<Bool> {
        Binding(
            get: { developerMode },
            set: { enabled in
                developerMode = enabled
                AppClock.resetSimulatedDay()
                SimulatedDayLedger.rollbackIfOnRealDay(context: context)
            }
        )
    }

    /// Binds a weekday's briefing time.
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
            set: {
                AppClock.setSimulatedDay($0)
                SimulatedDayLedger.rollbackIfOnRealDay(context: context)
            }
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
                    "Alles bleibt auf diesem Gerät. Es gibt kein Konto in der Cloud.",
                    "Everything stays on this device. There is no cloud account."
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
                    "Tippe einen Tag an, um das Briefing an- oder auszuschalten. Die Uhrzeit steht darunter.",
                    "Tap a day to turn the briefing on or off. The time sits underneath."
                ))
            }
            .appGlassRow()
            Section {
                Toggle(DeveloperCopy.toggle, isOn: developerModeBinding)
                if developerMode {
                    DatePicker(L("Aktueller Tag", "Current day"), selection: simulatedDay, displayedComponents: .date)
                    let _ = tradeRepublicSampleRevision
                    NavigationLink {
                        TradeRepublicSampleView()
                    } label: {
                        Label(TradeRepublicCopy.extract, systemImage: "doc.on.doc")
                    }
                }
            } footer: {
                Text(L(
                    "Der Tag gilt für Home, Challenges und den Kalender. Finanzen bleiben beim echten Datum.",
                    "The day applies to Home, challenges, and the calendar. Finance stays on the real date."
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

/// Profile settings.
private struct UserSettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var workouts: WorkoutStore
    @AppStorage("userName") private var userName = ""
    @AppStorage(UserProfile.birthKey) private var birthRaw = ""
    @AppStorage(ProfilePhotoStore.revisionKey) private var photoRevision = 0
    @State private var heightText = UserBody.heightText()
    @State private var weightText = UserBody.weightText()
    @State private var sex = UserBody.current().sex
    @State private var goal = UserBody.current().goal
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var libraryItem: PhotosPickerItem?

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
        let _ = photoRevision
        Form {
            Section {
                VStack(spacing: 10) {
                    ProfileAvatar(side: 88)
                    Menu {
                        if CameraCapture.isAvailable {
                            Button(L("Foto aufnehmen", "Take photo"), systemImage: "camera") {
                                showsCamera = true
                            }
                        }
                        Button(L("Galerie", "Library"), systemImage: "photo") {
                            showsLibrary = true
                        }
                        if ProfilePhotoStore.load() != nil {
                            Button(role: .destructive) {
                                ProfilePhotoStore.remove()
                            } label: {
                                Label(L("Bild entfernen", "Remove photo"), systemImage: "trash")
                            }
                        }
                    } label: {
                        Text(L("Profilbild", "Profile photo"))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
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
                        "Das Datum gilt, sobald du es änderst. Am Geburtstag gibt es 500 Coins. Größe, Gewicht und Ziel setzen das Kalorienziel.",
                        "The date is saved once you change it. Your birthday pays 500 coins. Height, weight, and the goal set the calorie target."
                    )
                    : L(
                        "Am Geburtstag gibt es 500 Coins. Größe, Gewicht und Ziel setzen das Kalorienziel.",
                        "Your birthday pays 500 coins. Height, weight, and the goal set the calorie target."
                    ))
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Nutzereinstellungen", "User settings"))
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showsLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    ProfilePhotoStore.save(data)
                }
                libraryItem = nil
            }
        }
        .sheet(isPresented: $showsCamera) {
            CameraCapture { data in
                ProfilePhotoStore.save(data)
                showsCamera = false
            } onCancel: {
                showsCamera = false
            }
        }
        .onChange(of: heightText) { storeBody() }
        .onChange(of: weightText) { storeBody() }
        .onChange(of: sex) { storeBody() }
        .onChange(of: goal) { storeBody() }
    }

    /// Stores the body data.
    private func storeBody() {
        UserBody.save(heightText: heightText, weightText: weightText, sex: sex, goal: goal)
        NutritionLedger.settle(context: context, sessions: workouts.sessions)
    }
}

/// The briefing times per weekday.
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

    /// Formats a weekday's time.
    private func timeLabel(_ weekday: Int) -> String {
        let clock = LififyNotifications.clock(for: weekday)
        return String(format: "%02d:%02d", clock.hour, clock.minute)
    }
}

/// Finance settings.
private struct FinanceSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]
    @AppStorage(TradeFeePreference.storageKey) private var defaultTradeFeeCents = TradeFeePreference.defaultCents
    @State private var feeText = ""
    @StateObject private var importModel = DataImportViewModel()
    @State private var importingBank = false
    @State private var importingTradeRepublic = false
    @AppStorage(PeriodReviewNotifier.enabledKey) private var reviewNotice = false
    @AppStorage(ReturnScenario.enabledKey) private var scenarioEnabled = false

    var body: some View {
        Form {
            FinanceLockSection()
            BudgetAlertSection()
            Section {
                Toggle(L("Mitteilung zum Monatsrückblick", "Notify about the monthly review"), isOn: $reviewNotice)
            } footer: {
                Text(L("Meldet sich einmal, wenn ein Zeitraum abgeschlossen ist.", "Notifies you once when a period has ended."))
            }
            .appGlassRow()
            Section {
                NavigationLink {
                    AccountsSettingsView()
                } label: {
                    Label(L("Konten", "Accounts"), systemImage: "building.columns")
                }
            }
            .appGlassRow()
            FinanceImportSettings(viewModel: importModel, importingBank: $importingBank)
            Section {
                NavigationLink {
                    ShortcutsSettingsView()
                } label: {
                    Label(L("Kurzbefehle", "Shortcuts"), systemImage: "bolt.fill")
                }
            }
            .appGlassRow()
            TradeRepublicSignInControls(
                showsSkip: false,
                onUploadStatement: { importingTradeRepublic = true }
            ) {}
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
                NavigationLink {
                    ReturnScenarioSettingsView()
                } label: {
                    LabeledContent(
                        L("Renditeszenario", "Return scenario"),
                        value: scenarioEnabled ? L("An", "On") : L("Aus", "Off")
                    )
                }
            } header: {
                Text(L("Depot", "Portfolio"))
            } footer: {
                Text(L(
                    "Jedes Depot hängt an einem Girokonto. Die Gebühr gilt einmal pro Buchung, nicht pro Stück.",
                    "Each portfolio is linked to one checking account. The fee applies once per booking, not per share."
                ))
            }
            .appGlassRow()
        }
        .appGlassList()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(L("Finanzen", "Finance"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $importingTradeRepublic,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                importModel.importTradeRepublic(from: url, context: context, existingEntries: entries)
            } else if case let .failure(error) = result {
                importModel.message = error.localizedDescription
            }
        }
        .sheet(item: $importModel.review) { review in
            ImportReviewSheet(review: review) { updated in
                importModel.finishReview(updated, context: context)
            }
        }
        .alert(L("Lifify", "Lifify"), isPresented: Binding(
            get: { importModel.message != nil && importModel.review == nil },
            set: { if !$0 { importModel.message = nil } }
        )) {
            Button("OK") { importModel.message = nil }
        } message: {
            Text(importModel.message ?? "")
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
    }

}

/// Challenge settings.
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
                    "Sport, Abstinenz und Sonstiges gibt es immer. Eine eigene Kategorie kann eine eigene Überschrift bekommen.",
                    "Sport, abstinence, and other always exist. A custom category can have its own heading."
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
                    "Ein Extra-Freeze kostet diesen Faktor mal die Basis-Belohnung. Standard ist 10.",
                    "An extra freeze costs this factor times the base reward. The default is 10."
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
                    "Der Faktor gilt auf die Basis-Belohnung. Bei mehreren Stufen zählt nur die höchste.",
                    "The factor applies to the base reward. When several steps are reached, only the highest one counts."
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
                    "Der Bonus ist dieser Faktor mal die Coins pro Tag. Jede erreichte Stufe zahlt.",
                    "The bonus is this factor times the coins per day. Every reached step pays."
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

/// Edits a streak multiplier.
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

/// Edits an abstinence multiplier.
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

/// One body measurement.
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

/// The profile photo.
private struct ProfileAvatar: View {
    var side: CGFloat
    @AppStorage(ProfilePhotoStore.revisionKey) private var revision = 0

    var body: some View {
        let _ = revision
        Group {
            if let data = ProfilePhotoStore.load(), let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
    }
}

/// Health settings.
private struct HealthSettingsView: View {
    @AppStorage(RestChime.storageKey) private var restChimeID = 1005
    @AppStorage(MealCapture.saveKey) private var saveMealPhotos = false
    @AppStorage(ProgressiveOverload.stepKey) private var overloadStep = ProgressiveOverload.defaultStepKg
    @State private var geminiKey = ""

    var body: some View {
        Form {
            Section {
                Toggle(L("Aufnahmen in der Galerie sichern", "Save new photos to the library"), isOn: $saveMealPhotos)
                SecureField(L("Gemini-Schlüssel", "Gemini key"), text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L("Ernährung", "Nutrition"))
            } footer: {
                Text(L(
                    "Fotos bleiben in der App. In die Galerie nur, wenn der Schalter an ist. Der Schlüssel bleibt auf dem Gerät.",
                    "Photos stay in the app. They reach the library only when the switch is on. The key stays on this device."
                ))
            }
            .appGlassRow()
            Section {
                NavigationLink {
                    RestChimePicker(selection: $restChimeID)
                } label: {
                    LabeledContent(L("Klingelton", "Chime"), value: RestChime.tones.first { $0.id == restChimeID }?.name ?? RestChime.selectedName)
                }
                Stepper(value: $overloadStep, in: 0.5...10, step: 0.5) {
                    LabeledContent(L("Gewichtsstufe", "Weight step"), value: "\(WorkoutFormat.weight(overloadStep)) kg")
                }
            } header: {
                Text(L("Training", "Training"))
            } footer: {
                Text(L(
                    "Der Ton beendet die Satzpause. Die Stufe erhöht den Gewichtsvorschlag, wenn im letzten Training alle Wiederholungen geschafft wurden.",
                    "The chime ends a rest period. The step raises the suggested weight when the last workout reached every rep."
                ))
            }
            .appGlassRow()
            AppleHealthSection()
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

/// Picks the rest sound.
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
