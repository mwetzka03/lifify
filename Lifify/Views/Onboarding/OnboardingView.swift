import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingBroker: Identifiable {
    var id: String { name }
    var name: String
    var supported: Bool

    static var all: [OnboardingBroker] {
        [
            OnboardingBroker(name: "Trade Republic", supported: true),
            OnboardingBroker(name: "Scalable Capital", supported: false),
            OnboardingBroker(name: "ING", supported: false),
            OnboardingBroker(name: "comdirect", supported: false),
            OnboardingBroker(name: "flatex", supported: false),
            OnboardingBroker(name: "Consorsbank", supported: false),
            OnboardingBroker(name: "Smartbroker", supported: false),
            OnboardingBroker(name: "justTRADE", supported: false)
        ]
    }
}

enum OnboardingSteps {
    static var title: String { L("Lifify einrichten", "Set up Lifify") }
    static var start: String { L("Wie möchtest du starten?", "How would you like to start?") }
    static var newSetup: String { L("Neu einrichten", "Set up as new") }
    static var restore: String { L("JSON-Sicherung oder Teile laden", "Restore a JSON backup or parts") }
    static var restoreNote: String {
        L(
            "Die ganze App, oder nur einzelne Bereiche: nur Finanzen, nur Challenges oder nur Gesundheit (Trainings und Mahlzeiten). Mehrere Dateien auf einmal gehen.",
            "The entire app, or only one area: Finance only, Challenges only, or Health only (workouts and meals). You can pick several files at once."
        )
    }
    static var welcome: String { L("Willkommen", "Welcome") }
    static var period: String { L("Budgetzeitraum", "Budget period") }
    static var account: String { L("Hauptkonto", "Main account") }
    static var bank: String { L("Hauptkonto importieren (optional)", "Import the main account (optional)") }
    static var tradeRepublic: String { "Trade Republic" }
    static var broker: String { L("Depot anlegen (optional)", "Add a portfolio (optional)") }
    static var tradeRepublicSignIn: String {
        L("Trade Republic anmelden (optional)", "Sign in to Trade Republic (optional)")
    }
    static let count = 9
    static var secondaryIncome: String { L("Nebeneinnahmen (optional)", "Secondary income (optional)") }
}

enum OnboardingResume {
    /// Unfinished setup always opens on the first step after a relaunch or update.
    static func launchStep(isComplete: Bool, savedStep: Int) -> Int {
        if isComplete { return 0 }
        _ = savedStep
        return 0
    }
}

private struct SecondaryIncomeDraft: Identifiable {
    let id = UUID()
    var rowID: UUID?
    var name = ""
    var iban = ""
    var amount = ""
    var date = Date.now
    var dueRule = DueRule.calendarDay
    var dueDay = 1
}

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var existingEntries: [LedgerEntry]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("userName") private var storedName = ""
    @AppStorage("dashboardPeriodMode") private var storedPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @State private var step = 0

    @State private var userName = ""
    @State private var birthDate = UserProfile.birthDate() ?? UserProfile.suggestedDate()
    @State private var initialBirth = UserProfile.birthDate() ?? UserProfile.suggestedDate()
    @State private var birthConfirmed = UserProfile.birth() != nil
    @State private var heightText = UserBody.heightText()
    @State private var weightText = UserBody.weightText()
    @State private var sex = UserBody.current().sex
    @State private var goal = UserBody.current().goal
    @State private var periodMode = DashboardPeriodMode.calendarMonth
    @State private var accountName = ""
    @State private var accountIBAN = ""
    @State private var mainAccountID: UUID?
    @State private var openingBalance = ""
    @State private var pendingImportRows: [ImportedTransaction] = []
    @State private var pendingDocument: BankImportDocument?
    @State private var importedRows: [ImportedTransaction] = []
    @State private var tradeRepublicRows: [ImportedTransaction] = []
    @State private var tradeRepublicImported = false
    @State private var tradeRepublicBooked = 0
    @State private var skippedBeforeStart = 0
    @State private var importedHoldingCount = 0
    @State private var importedAccountName = ""
    @State private var createdSeparateChecking = false
    @State private var importedEntryIDs: [String: UUID] = [:]
    @State private var primaryRowID: UUID?
    @State private var primaryName = ""
    @State private var primaryIBAN = ""
    @State private var primaryAmount = ""
    @State private var primaryDate = Date.now
    @State private var dueRule = DueRule.calendarDay
    @State private var dueDay = 1
    @State private var secondaryDrafts: [SecondaryIncomeDraft] = []
    @State private var importingBackup = false
    @State private var importingBank = false
    @State private var importingTradeRepublic = false
    @State private var isFinishing = false
    @State private var message: String?
    @State private var importReview: ImportReview?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(OnboardingSteps.count))
                    .padding()
                Form {
                    switch step {
                    case 0: languageStep
                    case 1: startStep
                    case 2: nameStep
                    case 3: periodStep
                    case 4: accountStep
                    case 5: bankImportStep
                    case 6: brokerStep
                    case 7: tradeRepublicStep
                    default: incomeStep
                    }
                }
                .appGlassList()
            }
            .navigationTitle(OnboardingSteps.title)
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $importingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: BackupScope.allowsSeveralFiles,
                onCompletion: restoreBackup
            )
            .fileImporter(
                isPresented: $importingBank,
                allowedContentTypes: [.commaSeparatedText, .xml, .plainText],
                allowsMultipleSelection: false,
                onCompletion: importBankFile
            )
            .fileImporter(
                isPresented: $importingTradeRepublic,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false,
                onCompletion: importTradeRepublicFile
            )
            .alert(L("Lifify", "Lifify"), isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .sheet(item: $importReview) { review in
                ImportReviewSheet(review: review) { updated in
                    do {
                        try BankImportApplier.commitReview(updated, context: context)
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            .onAppear {
                onboardingInProgress = true
                if userName.isEmpty { userName = storedName }
                if let stored = UserProfile.birthDate() {
                    birthDate = stored
                    initialBirth = stored
                    birthConfirmed = true
                }
            }
        }
    }

    @ViewBuilder
    private var languageStep: some View {
        Section {
            Picker("Language / Sprache", selection: $language) {
                Text("Deutsch").tag("de")
                Text("English").tag("en")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .appGlassRow()
        Section {
            nextButton { step = 1 }
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var startStep: some View {
        Section {
            backButton()
            Button {
                step = 2
            } label: {
                Label(OnboardingSteps.newSetup, systemImage: "sparkles")
            }
            Button {
                importingBackup = true
            } label: {
                Label(OnboardingSteps.restore, systemImage: "square.and.arrow.down")
            }
            Text(OnboardingSteps.restoreNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(OnboardingSteps.start)
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var nameStep: some View {
        Section {
            TextField(L("Dein Name", "Your name"), text: $userName)
            DatePicker(
                L("Geburtsdatum", "Date of birth"),
                selection: $birthDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .onChange(of: birthDate) {
                if UserProfile.birth() != nil || !Calendar.current.isDate(birthDate, inSameDayAs: initialBirth) {
                    birthConfirmed = true
                }
            }
            HStack {
                TextField("0", text: $heightText)
                    .keyboardType(.decimalPad)
                Text(L("Zentimeter", "Centimetres"))
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                Text(L("Kilogramm", "Kilograms"))
                    .foregroundStyle(.secondary)
            }
            Picker(L("Geschlecht", "Sex"), selection: $sex) {
                ForEach(BodySex.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Ziel", "Goal"), selection: $goal) {
                ForEach(BodyGoal.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text(OnboardingSteps.welcome)
        } footer: {
            Text(L(
                "Der Name wird nur lokal für deine Begrüßung verwendet. Stell das Geburtsdatum auf deinen Tag, dann geht es weiter. Größe, Gewicht und Ziel kannst du auch später unter Nutzereinstellungen setzen. Sie bestimmen das Kalorienziel. Am Geburtstag gibt es einmal im Jahr 500 Coins.",
                "The name is stored locally only for your greeting. Set the date of birth to your day, then you can continue. Height, weight, and the goal can also be set later under User settings. They set the calorie target. Your birthday pays 500 coins once each year."
            ))
        }
        .appGlassRow()
        Section {
            backButton()
            nextButton {
                storedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                UserProfile.setBirthDate(birthDate)
                UserBody.save(heightText: heightText, weightText: weightText, sex: sex, goal: goal)
                step = 3
            }
            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !birthConfirmed)
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var periodStep: some View {
        Section {
            Picker(OnboardingSteps.period, selection: $periodMode) {
                ForEach(DashboardPeriodMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(OnboardingSteps.period)
        }
        .appGlassRow()
        Section {
            backButton()
            nextButton {
                storedPeriod = periodMode.rawValue
                step = 4
            }
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var accountStep: some View {
        Section {
            TextField(L("Name des Hauptkontos", "Main account name"), text: $accountName)
            TextField("IBAN", text: $accountIBAN)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text(OnboardingSteps.account)
        } footer: {
            Text(L("Das Hauptkonto ist verpflichtend und kann später nicht gelöscht werden.", "The main account is required and cannot be deleted later."))
        }
        .appGlassRow()
        Section {
            backButton()
            nextButton {
                if saveMainAccount() { step = 5 }
            }
            .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var bankImportStep: some View {
        Section {
            if pendingImportRows.isEmpty && importedRows.isEmpty {
                Button {
                    importingBank = true
                } label: {
                    Label(L("CSV oder CAMT auswählen", "Select CSV or CAMT"), systemImage: "tablecells")
                }
            }
            if !pendingImportRows.isEmpty {
                Text(L(
                    "Wie hoch ist der aktuelle Kontostand?",
                    "What is the current account balance?"
                ))
                .font(.headline)
                TextField(L("Aktueller Kontostand", "Current balance"), text: $openingBalance)
                    .keyboardType(.decimalPad)
                Button(L("Import abschließen", "Finish import")) {
                    commitBankImport()
                }
                .disabled(Money.cents(from: openingBalance) == nil)
            }
            if !importedRows.isEmpty {
                Label(
                    "\(importedRows.count) \(L("Buchungen importiert", "transactions imported"))",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
        } header: {
            Text(OnboardingSteps.bank)
        } footer: {
            Text(L(
                "CSV oder CAMT aufs Hauptkonto. Du gibst den aktuellen Kontostand an, den Startsaldo rechnet Lifify zurück.",
                "CSV or CAMT onto the main account. You enter the current balance, and Lifify works the opening backwards."
            ))
        }
        .appGlassRow()
        Section {
            backButton()
            if !importedRows.isEmpty {
                nextButton { step = 6 }
            }
            Button(L("Ohne Import fortfahren", "Continue without import")) {
                pendingImportRows = []
                step = 6
            }
            .disabled(!importedRows.isEmpty)
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var tradeRepublicStep: some View {
        if let statement = pendingDocument?.tradeRepublic {
            Section {
                Text(String(
                    format: L(
                        "%d Buchungen erkannt. Endsaldo %@.",
                        "%d transactions found. Closing balance %@."
                    ),
                    statement.rows.count,
                    Money.string(cents: statement.closingBalanceCents)
                ))
                .font(.headline)
                Button(L("Import abschließen", "Finish import")) {
                    commitTradeRepublicImport()
                }
                Button(L("Andere Datei wählen", "Choose another file")) {
                    pendingDocument = nil
                }
            } header: {
                Text(OnboardingSteps.tradeRepublic)
            }
            .appGlassRow()
        }
        if tradeRepublicImported {
            Section {
                Label(
                    "\(tradeRepublicBooked) \(L("Buchungen importiert", "transactions imported"))",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                if createdSeparateChecking {
                    Text(String(
                        format: L("Separates Girokonto „%@“ angelegt.", "Created the separate checking account “%@”."),
                        importedAccountName
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if importedHoldingCount > 0 {
                    Text(String(
                        format: L("%d Depotpositionen übernommen.", "%d portfolio positions imported."),
                        importedHoldingCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .appGlassRow()
        }
        if pendingDocument == nil && !tradeRepublicImported {
            TradeRepublicSignInControls(
                showsSkip: false,
                onUploadStatement: { importingTradeRepublic = true },
                onSignedIn: {
                    tradeRepublicImported = true
                    step = 8
                }
            ) {}
        }
        Section {
            backButton()
            nextButton { step = 8 }
                .disabled(pendingDocument != nil && !tradeRepublicImported)
        } footer: {
            Text(firstPeriodNote)
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var brokerStep: some View {
        Section {
            ForEach(OnboardingBroker.all) { broker in
                if broker.supported {
                    Button {
                        createTradeRepublicAccounts()
                        step = 7
                    } label: {
                        HStack {
                            Text(broker.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text(broker.name)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L("Nicht unterstützt", "Not supported"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(OnboardingSteps.broker)
        } footer: {
            Text(L(
                "Trade Republic legt ein Girokonto an und verknüpft das Depot damit. Andere Broker folgen später.",
                "Trade Republic creates a checking account and links the portfolio to it. Other brokers come later."
            ))
        }
        .appGlassRow()
        Section {
            backButton()
            Button(L("Ohne Depot fortfahren", "Continue without a portfolio")) {
                step = 8
            }
        }
        .appGlassRow()
    }

    @ViewBuilder
    private var incomeStep: some View {
        Section(L("Haupteinnahme", "Primary income")) {
            if !positiveRows.isEmpty {
                Picker(L("Positive Buchung", "Positive transaction"), selection: $primaryRowID) {
                    Text(L("Manuell", "Manual")).tag(Optional<UUID>.none)
                    ForEach(positiveRows) {
                        Text("\($0.title) · \(Money.string(cents: $0.amountCents)) · \($0.senderIBAN.isEmpty ? L("keine IBAN", "no IBAN") : $0.senderIBAN)")
                            .tag(Optional($0.id))
                    }
                }
                .onChange(of: primaryRowID) { fillPrimaryIncome() }
            }
            TextField(L("Bezeichnung", "Name"), text: $primaryName)
            TextField("IBAN", text: $primaryIBAN)
                .textInputAutocapitalization(.characters)
            TextField(L("Prognosebetrag", "Forecast amount"), text: $primaryAmount)
                .keyboardType(.decimalPad)
            Picker(L("Fälligkeit", "Due date"), selection: $dueRule) {
                ForEach(DueRule.allCases) { Text($0.label).tag($0) }
            }
            if dueRule == .calendarDay {
                Stepper("\(L("Kalendertag", "Calendar day")): \(dueDay)", value: $dueDay, in: 1...31)
            }
        }
        .appGlassRow()
        Section {
            Button {
                secondaryDrafts.append(SecondaryIncomeDraft())
            } label: {
                Label(L("Nebeneinnahme hinzufügen", "Add secondary income"), systemImage: "plus")
            }
        } header: {
            Text(OnboardingSteps.secondaryIncome)
        }
        .appGlassRow()
        ForEach($secondaryDrafts) { draft in
            Section {
                if !positiveRows.isEmpty {
                    Picker(L("Positive Buchung", "Positive transaction"), selection: draft.rowID) {
                        Text(L("Manuell", "Manual")).tag(Optional<UUID>.none)
                        ForEach(positiveRows.filter { $0.id != primaryRowID }) { row in
                            Text("\(row.title) · \(Money.string(cents: row.amountCents)) · \(row.senderIBAN.isEmpty ? L("keine IBAN", "no IBAN") : row.senderIBAN)")
                                .tag(Optional(row.id))
                        }
                    }
                    .onChange(of: draft.wrappedValue.rowID) { fillSecondaryIncome(draft.wrappedValue.id) }
                }
                TextField(L("Bezeichnung", "Name"), text: draft.name)
                TextField("IBAN", text: draft.iban)
                    .textInputAutocapitalization(.characters)
                TextField(L("Prognosebetrag", "Forecast amount"), text: draft.amount)
                    .keyboardType(.decimalPad)
                Picker(L("Fälligkeit", "Due date"), selection: draft.dueRule) {
                    ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                }
                if draft.dueRule.wrappedValue == .calendarDay {
                    Stepper("\(L("Kalendertag", "Calendar day")): \(draft.dueDay.wrappedValue)", value: draft.dueDay, in: 1...31)
                }
                Button(L("Nebeneinnahme entfernen", "Remove secondary income"), role: .destructive) {
                    secondaryDrafts.removeAll { $0.id == draft.wrappedValue.id }
                }
            }
            .appGlassRow()
        }
        Section {
            backButton()
            Button {
                finishSetup()
            } label: {
                if isFinishing {
                    ProgressView()
                } else {
                    Text(L("Einrichtung abschließen", "Finish setup"))
                }
            }
            .disabled(!canFinish || isFinishing)
        }
        .appGlassRow()
    }

    private var positiveRows: [ImportedTransaction] {
        let rows = importedRows.isEmpty && tradeRepublicRows.isEmpty ? restoredImportedRows : importedRows + tradeRepublicRows
        return rows.filter { $0.amountCents > 0 && $0.trade == nil }.sorted { $0.date > $1.date }
    }

    private var firstPeriodNote: String {
        if let period = BankImportApplier.firstMainAccountPeriod(
            entries: existingEntries,
            accounts: accounts,
            context: context
        ) {
            return String(
                format: L(
                    "Erster Zeitraum des Hauptkontos: %@. Frühere Buchungen auf anderen Konten bleiben außerhalb davon.",
                    "First period of the main account: %@. Earlier bookings on other accounts stay outside it."
                ),
                AppDate.range(from: period.start, to: period.end)
            )
        }
        return L(
            "Ohne Buchungen auf dem Hauptkonto gibt es noch keinen Zeitraum. Dann werden alle Buchungen übernommen.",
            "Without bookings on the main account there is no period yet. Every transaction is imported."
        )
    }

    private var restoredImportedRows: [ImportedTransaction] {
        existingEntries.compactMap { entry in
            guard entry.kind != .transfer, let fingerprint = entry.importFingerprint else { return nil }
            let ibans = BankImportService.ibans(from: entry.notes, amountCents: entry.amountCents)
            return ImportedTransaction(
                id: entry.id,
                date: entry.date,
                title: entry.title,
                notes: entry.notes,
                amountCents: entry.amountCents,
                iban: entry.amountCents >= 0 ? ibans.sender : ibans.recipient,
                senderIBAN: ibans.sender,
                recipientIBAN: ibans.recipient,
                fingerprint: fingerprint
            )
        }
    }

    private var canFinish: Bool {
        !primaryName.trimmingCharacters(in: .whitespaces).isEmpty
            && (Money.cents(from: primaryAmount) ?? 0) > 0
    }

    private func nextButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(L("Weiter", "Continue"))
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
    }

    private func backButton() -> some View {
        Button {
            step = max(step - 1, 0)
        } label: {
            HStack {
                Image(systemName: "chevron.left")
                Text(L("Zurück", "Back"))
                Spacer()
            }
        }
    }

    private func createTradeRepublicAccounts() {
        let checking: Account
        if let existing = accounts.first(where: {
            $0.kind == .checking && $0.name.caseInsensitiveCompare("Trade Republic") == .orderedSame
        }) {
            checking = existing
        } else {
            let created = Account(name: "Trade Republic", kind: .checking, isLiquid: true, isMain: false)
            context.insert(created)
            checking = created
        }
        checking.isMain = false
        if PortfolioLinkStore.portfolioID(for: checking.id) == nil {
            let portfolio = Account(name: L("Depot", "Portfolio"), kind: .portfolio, isLiquid: false)
            context.insert(portfolio)
            PortfolioLinkStore.link(portfolio: portfolio.id, to: checking.id)
        }
        try? context.save()
    }

    private func saveMainAccount() -> Bool {
        let account = accounts.first(where: \.isMain) ?? Account(name: accountName, isMain: true)
        accounts.forEach { $0.isMain = false }
        account.name = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        account.kind = .checking
        account.isMain = true
        account.isLiquid = true
        account.iban = accountIBAN.replacingOccurrences(of: " ", with: "").uppercased()
        if account.modelContext == nil { context.insert(account) }
        do {
            try context.save()
            mainAccountID = account.id
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func importBankFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result { message = error.localizedDescription }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try BankImportService.parseDocument(
                data: Data(contentsOf: url),
                fileExtension: url.pathExtension
            )
            guard !document.rows.isEmpty else {
                message = L("Der Export enthält keine Buchungen.", "The export contains no transactions.")
                return
            }
            pendingDocument = nil
            pendingImportRows = document.rows.sorted { $0.date < $1.date }
        } catch {
            message = error.localizedDescription
        }
    }

    private func importTradeRepublicFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result { message = error.localizedDescription }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let document = try BankImportService.parseTradeRepublic(data: Data(contentsOf: url))
            guard !document.rows.isEmpty else {
                message = L("Der Auszug enthält keine Buchungen.", "The statement contains no transactions.")
                return
            }
            pendingDocument = document
            pendingImportRows = []
        } catch {
            message = error.localizedDescription
        }
    }

    private func commitTradeRepublicImport() {
        guard let document = pendingDocument else { return }
        do {
            let result = try BankImportApplier.apply(
                document: document,
                to: .separateChecking,
                detectDuplicates: false,
                context: context
            )
            importedEntryIDs.merge(result.entryIDs) { _, new in new }
            tradeRepublicRows = result.selectableRows
            tradeRepublicBooked = result.importedCount
            importedHoldingCount = result.holdingCount
            importedAccountName = result.accountName
            createdSeparateChecking = result.createdSeparateChecking
            skippedBeforeStart = result.skippedBeforeStart
            tradeRepublicImported = true
            pendingDocument = nil
            importReview = result.review.isEmpty ? nil : result.review
        } catch {
            message = error.localizedDescription
        }
    }

    private func commitBankImport() {
        guard let accountID = mainAccountID ?? accounts.first(where: \.isMain)?.id,
              let account = accounts.first(where: { $0.id == accountID }),
              let current = Money.cents(from: openingBalance),
              let firstDate = pendingImportRows.first?.date
        else {
            return
        }
        var ledger = existingEntries
        var known = Set<String>()
        var review = ImportReview()
        var selectableRows: [ImportedTransaction] = []
        var entryIDs: [String: UUID] = [:]
        var inserted: [LedgerEntry] = []
        if !existingEntries.contains(where: {
            $0.kind == .adjustment
                && $0.accountID == accountID
                && !ImportBalance.isCurrentPin($0, accountID: accountID)
        }) {
            let opening = ImportBalance.openingCents(
                current: current,
                rowAmounts: pendingImportRows.map(\.amountCents)
            )
            let day = Calendar.current.startOfDay(for: firstDate)
            let adjustment = LedgerEntry(
                date: day,
                title: L("Eröffnungssaldo", "Opening balance"),
                amountCents: opening,
                kind: .adjustment,
                accountID: accountID,
                createdAt: day
            )
            context.insert(adjustment)
            inserted.append(adjustment)
            ledger.append(adjustment)
        }
        for row in pendingImportRows {
            guard let entry = BankImportApplier.ingestCashRow(
                row,
                checking: account,
                accounts: accounts,
                entries: &ledger,
                known: &known,
                review: &review,
                detectDuplicates: false,
                context: context
            ) else { continue }
            inserted.append(entry)
            selectableRows.append(row)
            entryIDs[row.fingerprint] = entry.id
        }
        let knownIDs = Set(inserted.map(\.id))
        if let extra = ImportBalance.fitToCurrent(
            account: account,
            entries: &ledger,
            currentCents: current,
            context: context
        ), !knownIDs.contains(extra.id) {
            inserted.append(extra)
        }
        do {
            try context.save()
            BankImportCursor.mark(accountID, currentCents: current)
            importedEntryIDs.merge(entryIDs) { _, new in new }
            importedRows = selectableRows
            pendingImportRows = []
            importReview = nil
        } catch {
            inserted.forEach(context.delete)
            message = error.localizedDescription
        }
    }

    private func fillPrimaryIncome() {
        guard let row = positiveRows.first(where: { $0.id == primaryRowID }) else { return }
        primaryName = row.title
        primaryIBAN = row.senderIBAN
        primaryAmount = String(format: "%.2f", Double(row.amountCents) / 100)
        primaryDate = row.date
        dueDay = Calendar.current.component(.day, from: row.date)
    }

    private func fillSecondaryIncome(_ draftID: UUID) {
        guard let index = secondaryDrafts.firstIndex(where: { $0.id == draftID }),
              let row = positiveRows.first(where: { $0.id == secondaryDrafts[index].rowID })
        else {
            return
        }
        secondaryDrafts[index].name = row.title
        secondaryDrafts[index].iban = row.senderIBAN
        secondaryDrafts[index].amount = String(format: "%.2f", Double(row.amountCents) / 100)
        secondaryDrafts[index].date = row.date
        secondaryDrafts[index].dueDay = Calendar.current.component(.day, from: row.date)
    }

    private func finishSetup() {
        guard !isFinishing,
              let amount = Money.cents(from: primaryAmount),
              amount > 0
        else {
            return
        }
        isFinishing = true
        guard let accountID = mainAccountID ?? accounts.first(where: \.isMain)?.id else {
            isFinishing = false
            message = L(
                "Das Hauptkonto fehlt. Bitte gehe zurück und speichere es erneut.",
                "The main account is missing. Go back and save it again."
            )
            return
        }
        let primaryForecast = IncomeForecast(
            name: primaryName.trimmingCharacters(in: .whitespacesAndNewlines),
            amountCents: amount,
            accountID: accountID,
            cadence: .monthly,
            firstPaymentDate: primaryDate,
            dueRule: dueRule,
            dayOfMonth: dueDay
        )
        context.insert(primaryForecast)

        var secondaryForecasts: [(draft: SecondaryIncomeDraft, forecast: IncomeForecast)] = []
        for draft in secondaryDrafts {
            guard let amount = Money.cents(from: draft.amount),
                  amount > 0,
                  !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            let forecast = IncomeForecast(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                amountCents: amount,
                accountID: accountID,
                cadence: .monthly,
                firstPaymentDate: draft.date,
                dueRule: draft.dueRule,
                dayOfMonth: draft.dueDay
            )
            context.insert(forecast)
            secondaryForecasts.append((draft, forecast))
        }
        do {
            try context.save()
        } catch {
            context.delete(primaryForecast)
            secondaryForecasts.forEach { context.delete($0.forecast) }
            isFinishing = false
            message = error.localizedDescription
            return
        }

        IncomeAssignmentStore.setPrimary(iban: primaryIBAN, forecastID: primaryForecast.id)
        if let row = positiveRows.first(where: { $0.id == primaryRowID }) {
            let entryID = importedEntryIDs[row.fingerprint] ?? row.id
            IncomeAssignmentStore.assign(entryID: entryID, to: primaryForecast.id)
        }
        IncomeAssignmentStore.setSecondary(secondaryForecasts.map {
            (iban: $0.draft.iban, forecastID: $0.forecast.id)
        })
        for pair in secondaryForecasts {
            guard let row = positiveRows.first(where: { $0.id == pair.draft.rowID }) else { continue }
            let entryID = importedEntryIDs[row.fingerprint] ?? row.id
            IncomeAssignmentStore.assign(entryID: entryID, to: pair.forecast.id)
        }
        isFinishing = false
        step = 0
        onboardingInProgress = false
        hasCompletedOnboarding = true
        BirthdayBonusService.settle(context: context)
    }

    private func restoreBackup(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, !urls.isEmpty else {
            if case let .failure(error) = result { message = error.localizedDescription }
            return
        }
        var accessors: [URL] = []
        defer { accessors.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            var payloads: [Data] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() { accessors.append(url) }
                payloads.append(try Data(contentsOf: url))
            }
            let scopes = try BackupService.restore(payloads: payloads, into: context)
            let restoredAccounts = try context.fetch(FetchDescriptor<Account>())
            guard restoredAccounts.contains(where: \.isMain) else {
                step = 4
                message = BackupService.restoredMessage(scopes) + " " + L(
                    "Die Sicherung enthält kein Hauptkonto. Bitte richte jetzt eines ein.",
                    "The backup contains no main account. Set one up now."
                )
                return
            }
            step = 0
            onboardingInProgress = false
            hasCompletedOnboarding = true
            BirthdayBonusService.settle(context: context)
        } catch {
            message = error.localizedDescription
        }
    }
}
