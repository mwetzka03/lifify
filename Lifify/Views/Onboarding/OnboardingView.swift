import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [Account]
    @Query private var existingEntries: [LedgerEntry]
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("userName") private var storedName = ""
    @AppStorage("dashboardPeriodMode") private var storedPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @AppStorage("onboardingStep") private var step = 0

    @State private var userName = ""
    @State private var periodMode = DashboardPeriodMode.calendarMonth
    @State private var accountName = ""
    @State private var accountIBAN = ""
    @State private var mainAccountID: UUID?
    @State private var openingBalance = ""
    @State private var importedRows: [ImportedTransaction] = []
    @State private var importedEntryIDs: [String: UUID] = [:]
    @State private var primaryRowID: UUID?
    @State private var primaryName = ""
    @State private var primaryIBAN = ""
    @State private var primaryAmount = ""
    @State private var primaryDate = Date.now
    @State private var dueRule = DueRule.calendarDay
    @State private var dueDay = 1
    @State private var secondaryRowIDs: Set<UUID> = []
    @State private var importingBackup = false
    @State private var importingBank = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 7)
                    .padding()
                Form {
                    switch step {
                    case 0: languageStep
                    case 1: startStep
                    case 2: nameStep
                    case 3: periodStep
                    case 4: accountStep
                    case 5: importStep
                    default: incomeStep
                    }
                }
            }
            .navigationTitle(L("Lifify einrichten", "Set up Lifify"))
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $importingBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false,
                onCompletion: restoreBackup
            )
            .fileImporter(
                isPresented: $importingBank,
                allowedContentTypes: [.commaSeparatedText, .xml, .plainText],
                allowsMultipleSelection: false,
                onCompletion: importBankFile
            )
            .alert(L("Lifify", "Lifify"), isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
            .onAppear { onboardingInProgress = true }
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
            nextButton { step = 1 }
        } header: {
            Text("Language / Sprache")
        }
    }

    @ViewBuilder
    private var startStep: some View {
        Section {
            Button {
                step = 2
            } label: {
                Label(L("Neu einrichten", "Set up as new"), systemImage: "sparkles")
            }
            Button {
                importingBackup = true
            } label: {
                Label(L("JSON-Sicherung laden", "Restore JSON backup"), systemImage: "square.and.arrow.down")
            }
        } header: {
            Text(L("Wie möchtest du starten?", "How would you like to start?"))
        }
    }

    @ViewBuilder
    private var nameStep: some View {
        Section {
            TextField(L("Dein Name", "Your name"), text: $userName)
            nextButton {
                storedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                step = 3
            }
            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(L("Willkommen", "Welcome"))
        } footer: {
            Text(L("Der Name wird nur lokal für deine Begrüßung verwendet.", "The name is stored locally only for your greeting."))
        }
    }

    @ViewBuilder
    private var periodStep: some View {
        Section {
            Picker(L("Dashboard-Zeitraum", "Dashboard period"), selection: $periodMode) {
                ForEach(DashboardPeriodMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            nextButton {
                storedPeriod = periodMode.rawValue
                step = 4
            }
        } header: {
            Text(L("Budgetzeitraum", "Budget period"))
        }
    }

    @ViewBuilder
    private var accountStep: some View {
        Section {
            TextField(L("Name des Hauptkontos", "Main account name"), text: $accountName)
            TextField("IBAN", text: $accountIBAN)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            nextButton {
                if saveMainAccount() { step = 5 }
            }
            .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(L("Hauptkonto", "Main account"))
        } footer: {
            Text(L("Das Hauptkonto ist verpflichtend und kann später nicht gelöscht werden.", "The main account is required and cannot be deleted later."))
        }
    }

    @ViewBuilder
    private var importStep: some View {
        Section {
            TextField(L("Kontostand vor dem ersten Export-Eintrag", "Balance before the first export entry"), text: $openingBalance)
                .keyboardType(.decimalPad)
            Button {
                guard Money.cents(from: openingBalance) != nil else {
                    message = L("Bitte zuerst den vorherigen Kontostand eingeben.", "Enter the previous account balance first.")
                    return
                }
                importingBank = true
            } label: {
                Label(L("CSV oder CAMT importieren", "Import CSV or CAMT"), systemImage: "doc.badge.plus")
            }
            .disabled(!importedRows.isEmpty)
            if !importedRows.isEmpty {
                Label(
                    "\(importedRows.count) \(L("Buchungen importiert", "transactions imported"))",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
            nextButton { step = 6 }
            Button(L("Ohne Import fortfahren", "Continue without import")) {
                step = 6
            }
            .disabled(!importedRows.isEmpty)
        } header: {
            Text(L("Bankexport (optional)", "Bank export (optional)"))
        }
    }

    @ViewBuilder
    private var incomeStep: some View {
        Section(L("Haupteinnahme", "Primary income")) {
            if !positiveRows.isEmpty {
                Picker(L("Positive Buchung", "Positive transaction"), selection: $primaryRowID) {
                    Text(L("Manuell", "Manual")).tag(Optional<UUID>.none)
                    ForEach(positiveRows) {
                        Text("\($0.title) · \(Money.string(cents: $0.amountCents))")
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
        if positiveRows.count > 1 {
            Section(L("Nebeneinnahmen (optional)", "Secondary income (optional)")) {
                ForEach(positiveRows.filter { $0.id != primaryRowID }) { row in
                    Toggle(isOn: Binding(
                        get: { secondaryRowIDs.contains(row.id) },
                        set: { enabled in
                            if enabled { secondaryRowIDs.insert(row.id) }
                            else { secondaryRowIDs.remove(row.id) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(row.title)
                            Text(Money.string(cents: row.amountCents))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        Section {
            Button(L("Einrichtung abschließen", "Finish setup")) {
                finishSetup()
            }
            .disabled(!canFinish)
        }
    }

    private var positiveRows: [ImportedTransaction] {
        let rows = importedRows.isEmpty ? restoredImportedRows : importedRows
        return rows.filter { $0.amountCents > 0 }.sorted { $0.date > $1.date }
    }

    private var restoredImportedRows: [ImportedTransaction] {
        existingEntries.compactMap { entry in
            guard let fingerprint = entry.importFingerprint else { return nil }
            return ImportedTransaction(
                id: entry.id,
                date: entry.date,
                title: entry.title,
                notes: entry.notes,
                amountCents: entry.amountCents,
                iban: entry.notes,
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
        guard case let .success(urls) = result, let url = urls.first,
              let accountID = mainAccountID ?? accounts.first(where: \.isMain)?.id,
              let balance = Money.cents(from: openingBalance)
        else {
            if case let .failure(error) = result { message = error.localizedDescription }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let parsedRows = try BankImportService.parse(
                data: Data(contentsOf: url),
                fileExtension: url.pathExtension
            ).sorted { $0.date < $1.date }
            guard let firstDate = parsedRows.first?.date else {
                message = L("Der Export enthält keine Buchungen.", "The export contains no transactions.")
                return
            }
            let knownFingerprints = Set(existingEntries.compactMap(\.importFingerprint))
            let rows = parsedRows.filter { !knownFingerprints.contains($0.fingerprint) }
            if !existingEntries.contains(where: {
                $0.kind == .adjustment && $0.accountID == accountID
            }) {
                let adjustmentDate = Calendar.current.date(byAdding: .day, value: -1, to: firstDate) ?? firstDate
                context.insert(LedgerEntry(
                    date: adjustmentDate,
                    title: L("Eröffnungssaldo", "Opening balance"),
                    amountCents: balance,
                    kind: .adjustment,
                    accountID: accountID
                ))
            }
            for row in rows {
                let entry = LedgerEntry(
                    date: row.date,
                    title: row.title,
                    notes: row.notes,
                    amountCents: row.amountCents,
                    kind: row.amountCents < 0 ? .expense : .income,
                    accountID: accountID,
                    importFingerprint: row.fingerprint
                )
                context.insert(entry)
                importedEntryIDs[row.fingerprint] = entry.id
            }
            try context.save()
            importedRows = parsedRows
        } catch {
            message = error.localizedDescription
        }
    }

    private func fillPrimaryIncome() {
        guard let row = positiveRows.first(where: { $0.id == primaryRowID }) else { return }
        primaryName = row.title
        primaryIBAN = row.iban
        primaryAmount = String(format: "%.2f", Double(row.amountCents) / 100)
        primaryDate = row.date
        dueDay = Calendar.current.component(.day, from: row.date)
    }

    private func finishSetup() {
        guard let amount = Money.cents(from: primaryAmount), amount > 0 else { return }
        let accountID = mainAccountID ?? accounts.first(where: \.isMain)?.id
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

        var secondaryForecasts: [(row: ImportedTransaction, forecast: IncomeForecast)] = []
        for row in positiveRows where secondaryRowIDs.contains(row.id) {
            let forecast = IncomeForecast(
                name: row.title,
                amountCents: row.amountCents,
                accountID: accountID,
                cadence: .monthly,
                firstPaymentDate: row.date,
                dueRule: dueRule,
                dayOfMonth: Calendar.current.component(.day, from: row.date)
            )
            context.insert(forecast)
            secondaryForecasts.append((row, forecast))
        }
        do {
            try context.save()
        } catch {
            context.delete(primaryForecast)
            secondaryForecasts.forEach { context.delete($0.forecast) }
            message = error.localizedDescription
            return
        }

        IncomeAssignmentStore.setPrimary(iban: primaryIBAN, forecastID: primaryForecast.id)
        if let row = positiveRows.first(where: { $0.id == primaryRowID }) {
            let entryID = importedEntryIDs[row.fingerprint] ?? row.id
            IncomeAssignmentStore.assign(entryID: entryID, to: primaryForecast.id)
        }
        IncomeAssignmentStore.setSecondary(secondaryForecasts.map {
            (iban: $0.row.iban, forecastID: $0.forecast.id)
        })
        for pair in secondaryForecasts {
            let entryID = importedEntryIDs[pair.row.fingerprint] ?? pair.row.id
            IncomeAssignmentStore.assign(entryID: entryID, to: pair.forecast.id)
        }
        step = 0
        onboardingInProgress = false
        hasCompletedOnboarding = true
    }

    private func restoreBackup(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case let .failure(error) = result { message = error.localizedDescription }
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try BackupService.restore(data: Data(contentsOf: url), into: context)
            let restoredAccounts = try context.fetch(FetchDescriptor<Account>())
            guard restoredAccounts.contains(where: \.isMain) else {
                step = 4
                message = L(
                    "Die Sicherung enthält kein Hauptkonto. Bitte richte jetzt eines ein.",
                    "The backup contains no main account. Set one up now."
                )
                return
            }
            step = 0
            onboardingInProgress = false
            hasCompletedOnboarding = true
        } catch {
            message = error.localizedDescription
        }
    }
}
