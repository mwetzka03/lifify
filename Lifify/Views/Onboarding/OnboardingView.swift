import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage("onboardingStep") private var step = 0

    @State private var userName = ""
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
    @State private var skippedOutsidePeriod = 0
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 8)
                    .padding()
                Form {
                    switch step {
                    case 0: languageStep
                    case 1: startStep
                    case 2: nameStep
                    case 3: periodStep
                    case 4: accountStep
                    case 5: bankImportStep
                    case 6: tradeRepublicStep
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
            .labelsHidden()
        }
        Section {
            nextButton { step = 1 }
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
        } header: {
            Text(L("Willkommen", "Welcome"))
        } footer: {
            Text(L("Der Name wird nur lokal für deine Begrüßung verwendet.", "The name is stored locally only for your greeting."))
        }
        Section {
            nextButton {
                storedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                step = 3
            }
            .disabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var periodStep: some View {
        Section {
            Picker(L("Budgetzeitraum", "Budget period"), selection: $periodMode) {
                ForEach(DashboardPeriodMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text(L("Budgetzeitraum", "Budget period"))
        }
        Section {
            nextButton {
                storedPeriod = periodMode.rawValue
                step = 4
            }
        }
    }

    @ViewBuilder
    private var accountStep: some View {
        Section {
            TextField(L("Name des Hauptkontos", "Main account name"), text: $accountName)
            TextField("IBAN", text: $accountIBAN)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        } header: {
            Text(L("Hauptkonto", "Main account"))
        } footer: {
            Text(L("Das Hauptkonto ist verpflichtend und kann später nicht gelöscht werden.", "The main account is required and cannot be deleted later."))
        }
        Section {
            nextButton {
                if saveMainAccount() { step = 5 }
            }
            .disabled(accountName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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
            if let balanceDate = openingBalanceDate, !pendingImportRows.isEmpty {
                Text(String(
                    format: L(
                        "Wie hoch war der Kontostand am %@?",
                        "What was the account balance on %@?"
                    ),
                    AppDate.weekdayAndNumeric(balanceDate)
                ))
                .font(.headline)
                TextField(L("Kontostand", "Account balance"), text: $openingBalance)
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
            Text(L("Hauptkonto importieren (optional)", "Import the main account (optional)"))
        } footer: {
            Text(L(
                "CSV und CAMT landen auf dem Hauptkonto und legen den ersten Zeitraum fest. Der Trade-Republic-Auszug folgt als eigener Schritt.",
                "CSV and CAMT go to the main account and define the first period. The Trade Republic statement follows as its own step."
            ))
        }
        Section {
            if !importedRows.isEmpty {
                nextButton { step = 6 }
            }
            Button(L("Ohne Import fortfahren", "Continue without import")) {
                pendingImportRows = []
                step = 6
            }
            .disabled(!importedRows.isEmpty)
        }
    }

    @ViewBuilder
    private var tradeRepublicStep: some View {
        Section {
            if !tradeRepublicImported && pendingDocument == nil {
                Button {
                    importingTradeRepublic = true
                } label: {
                    Label(L("Trade-Republic-Kontoauszug hochladen", "Upload a Trade Republic statement"), systemImage: "doc.badge.plus")
                }
            }
            if let statement = pendingDocument?.tradeRepublic {
                Text(String(
                    format: L(
                        "%d Buchungen erkannt. Endsaldo %@.",
                        "%d transactions found. Closing balance %@."
                    ),
                    statement.rows.count,
                    Money.string(cents: statement.closingBalanceCents)
                ))
                .font(.headline)
                Text(L(
                    "Daraus wird ein separates Trade-Republic-Girokonto. Ist die IBAN schon vorhanden, wird dieses Konto verwendet. Das Depot hängt daran.",
                    "This creates a separate Trade Republic checking account. An existing IBAN is reused. The portfolio is linked to it."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(L("Import abschließen", "Finish import")) {
                    commitTradeRepublicImport()
                }
                Button(L("Andere Datei wählen", "Choose another file")) {
                    pendingDocument = nil
                }
            }
            if tradeRepublicImported {
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
                if skippedOutsidePeriod > 0 {
                    Text(L(
                        "Buchungen außerhalb des ersten Zeitraums wurden nicht angelegt. Die Depotstände sind vollständig.",
                        "Transactions outside the first period were not booked. The portfolio positions are complete."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text(firstPeriodNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Trade Republic")
        } footer: {
            Text(L(
                "Kein Zielkonto. Der Startsaldo des ersten Zeitraums ist der Saldo aus der rechten Spalte am Starttag, sonst vom letzten Tag davor.",
                "No destination account. The opening balance of the first period is the right-hand balance on the start day, or from the previous day."
            ))
        }
        Section {
            if tradeRepublicImported {
                nextButton { step = 7 }
            }
            Button(L("Ohne Import fortfahren", "Continue without import")) {
                pendingDocument = nil
                step = 7
            }
            .disabled(tradeRepublicImported)
        }
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
        Section {
            Button {
                secondaryDrafts.append(SecondaryIncomeDraft())
            } label: {
                Label(L("Nebeneinnahme hinzufügen", "Add secondary income"), systemImage: "plus")
            }
        } header: {
            Text(L("Nebeneinnahmen (optional)", "Secondary income (optional)"))
        }
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
        }
        Section {
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
                    "Erster Zeitraum des Hauptkontos: %@. Buchungen außerhalb davon werden nicht angelegt. Depotstände aus dem ganzen Auszug werden übernommen. Der Startsaldo ist der Saldo am %@, sonst vom letzten Tag davor.",
                    "First period of the main account: %@. Transactions outside it are not booked. Portfolio positions from the whole statement are imported. The opening balance is the balance on %@, or the previous day."
                ),
                AppDate.range(from: period.start, to: period.end),
                AppDate.numeric(period.start)
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

    private var openingBalanceDate: Date? {
        guard let firstDate = pendingImportRows.first?.date else { return nil }
        return Calendar.current.date(byAdding: .day, value: -1, to: firstDate)
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
                openingBalanceCents: nil,
                context: context
            )
            importedEntryIDs.merge(result.entryIDs) { _, new in new }
            tradeRepublicRows = result.selectableRows
            tradeRepublicBooked = result.importedCount
            importedHoldingCount = result.holdingCount
            importedAccountName = result.accountName
            createdSeparateChecking = result.createdSeparateChecking
            skippedOutsidePeriod = result.skippedOutsidePeriod
            tradeRepublicImported = true
            pendingDocument = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func commitBankImport() {
        guard let accountID = mainAccountID ?? accounts.first(where: \.isMain)?.id,
              let balance = Money.cents(from: openingBalance),
              let firstDate = pendingImportRows.first?.date
        else {
            return
        }
        var existingByFingerprint: [String: LedgerEntry] = [:]
        for entry in existingEntries {
            if let fingerprint = entry.importFingerprint {
                existingByFingerprint[fingerprint] = entry
            }
        }
        var seenFingerprints: Set<String> = []
        var selectableRows: [ImportedTransaction] = []
        var entryIDs: [String: UUID] = [:]
        var inserted: [LedgerEntry] = []
        if !existingEntries.contains(where: {
            $0.kind == .adjustment && $0.accountID == accountID
        }) {
            let adjustment = LedgerEntry(
                date: Calendar.current.date(byAdding: .day, value: -1, to: firstDate) ?? firstDate,
                title: L("Eröffnungssaldo", "Opening balance"),
                amountCents: balance,
                kind: .adjustment,
                accountID: accountID
            )
            context.insert(adjustment)
            inserted.append(adjustment)
        }
        for row in pendingImportRows {
            let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
            guard seenFingerprints.isDisjoint(with: fingerprints) else { continue }
            seenFingerprints.formUnion(fingerprints)

            if let existing = fingerprints.compactMap({ existingByFingerprint[$0] }).first {
                selectableRows.append(ImportedTransaction(
                    id: existing.id,
                    date: row.date,
                    title: row.title,
                    notes: row.notes,
                    amountCents: row.amountCents,
                    iban: row.iban,
                    senderIBAN: row.senderIBAN,
                    recipientIBAN: row.recipientIBAN,
                    fingerprint: row.fingerprint,
                    legacyFingerprint: row.legacyFingerprint
                ))
                entryIDs[row.fingerprint] = existing.id
                continue
            }
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
            inserted.append(entry)
            selectableRows.append(row)
            entryIDs[row.fingerprint] = entry.id
        }
        do {
            try context.save()
            importedEntryIDs.merge(entryIDs) { _, new in new }
            importedRows = selectableRows
            pendingImportRows = []
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
