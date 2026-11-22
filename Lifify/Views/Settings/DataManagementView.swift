import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var fixedCosts: [FixedCost]
    @Query private var variableBudgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var forecasts: [IncomeForecast]
    @Query private var shopping: [ShoppingItem]
    @Query private var debts: [DebtEntry]
    @Query private var groups: [ExpenseGroup]
    @Query private var lines: [ExpenseGroupLine]
    @Query private var holdings: [PortfolioHolding]
    @Query private var calendarEvents: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @Query private var completions: [ChallengeCompletion]
    @Query private var challengeGroups: [ChallengeGroup]
    @Query private var coinTransactions: [CoinTransaction]
    @Query private var rewards: [RewardItem]
    @Query private var purchases: [RewardPurchase]
    @Query private var bucketItems: [BucketListItem]
    @StateObject private var viewModel = DataImportViewModel()
    @EnvironmentObject private var workouts: WorkoutStore
    @State private var importingBackup = false
    @State private var exportingBackup = false
    @State private var backupDocument = BackupDocument()
    @State private var exportFilename = "Lifify"
    @State private var destructiveAction: DestructiveAction?
    @State private var resetError: String?
    @AppStorage("appLanguage") private var language = "de"
    @AppStorage("appTheme") private var theme = AppTheme.system.rawValue
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingInProgress") private var onboardingInProgress = false
    @AppStorage("userName") private var userName = ""
    @AppStorage("dashboardPeriodMode") private var dashboardPeriod = DashboardPeriodMode.calendarMonth.rawValue
    @AppStorage("onboardingStep") private var onboardingStep = 0
    @AppStorage(TradeFeePreference.storageKey) private var defaultTradeFeeCents = TradeFeePreference.defaultCents
    @AppStorage(TradeAccountPreference.storageKey) private var defaultCheckingAccountID = ""

    var body: some View {
        Form {
            Section(L("JSON-Sicherung", "JSON backup")) {
                Button {
                    createBackup(.all)
                } label: {
                    Label(L("Gesamte App exportieren", "Export entire app"), systemImage: "square.and.arrow.up")
                }
                Button {
                    createBackup(.finance)
                } label: {
                    Label(L("Finanzen exportieren", "Export finance"), systemImage: "eurosign.circle")
                }
                Button {
                    createBackup(.challenges)
                } label: {
                    Label(L("Challenges und Kalender exportieren", "Export challenges and calendar"), systemImage: "target")
                }
                Button {
                    createBackup(.training)
                } label: {
                    Label(L("Gesundheit exportieren (Training und Mahlzeiten)", "Export health (training and meals)"), systemImage: "heart.text.square")
                }
                Button {
                    importingBackup = true
                } label: {
                    Label(L("Sicherung wiederherstellen", "Restore backup"), systemImage: "arrow.clockwise.icloud")
                }
                Text(L(
                    "Eine Teilsicherung ersetzt nur diesen Bereich. Eine volle Sicherung ersetzt alles. Fotos sind nicht enthalten.",
                    "A partial backup replaces only that area. A full backup replaces everything. Photos are not included."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .appGlassRow()

            Section {
                Button(role: .destructive) {
                    destructiveAction = .deleteFinance
                } label: {
                    Label(L("Finanzen löschen", "Delete finance"), systemImage: "eurosign.circle")
                }
                Button(role: .destructive) {
                    destructiveAction = .deleteTraining
                } label: {
                    Label(L("Training löschen", "Delete training"), systemImage: "figure.strengthtraining.traditional")
                }
                Button(role: .destructive) {
                    destructiveAction = .deleteChallenges
                } label: {
                    Label(L("Challenges löschen", "Delete challenges"), systemImage: "target")
                }
                Button(role: .destructive) {
                    destructiveAction = .deleteData
                } label: {
                    Label(L("Alle Daten löschen", "Delete all data"), systemImage: "trash")
                }
                Button(role: .destructive) {
                    destructiveAction = .resetApp
                } label: {
                    Label(L("App zurücksetzen", "Reset app"), systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text(L("Zurücksetzen", "Reset"))
            }
            .appGlassRow()
        }
        .appGlassList()
        .navigationTitle(L("Daten", "Data"))
        .navigationBarTitleDisplayMode(.inline)
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
                runDestructiveAction()
            }
        } message: {
            Text(destructiveAction?.message ?? "")
        }
        .alert(L("Zurücksetzen fehlgeschlagen", "Reset failed"), isPresented: Binding(
            get: { resetError != nil },
            set: { if !$0 { resetError = nil } }
        )) {
            Button("OK") { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: BackupScope.allowsSeveralFiles
        ) { result in
            if case let .success(urls) = result, !urls.isEmpty {
                viewModel.restoreBackups(from: urls, context: context)
            } else if case let .failure(error) = result {
                viewModel.message = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $exportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result { viewModel.message = error.localizedDescription }
        }
        .alert(L("Lifify", "Lifify"), isPresented: Binding(
            get: { viewModel.message != nil && viewModel.review == nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("OK") { viewModel.message = nil }
        } message: {
            Text(viewModel.message ?? "")
        }
    }

    private func createBackup(_ scope: BackupScope) {
        do {
            let snapshot = try workouts.exportSnapshotData()
            backupDocument = BackupDocument(data: try BackupService.exportData(
                accounts: accounts,
                entries: entries,
                splits: splits,
                fixedCosts: fixedCosts,
                variableBudgets: variableBudgets,
                pools: pools,
                forecasts: forecasts,
                shopping: shopping,
                debts: debts,
                groups: groups,
                lines: lines,
                holdings: holdings,
                calendarEvents: calendarEvents,
                challenges: challenges,
                completions: completions,
                challengeGroups: challengeGroups,
                coinTransactions: coinTransactions,
                rewards: rewards,
                purchases: purchases,
                bucketItems: bucketItems,
                scope: scope,
                workoutSnapshot: snapshot
            ))
            exportFilename = "\(scope.exportFilenamePrefix)-\(Date.now.dayKey)"
            exportingBackup = true
        } catch {
            viewModel.message = error.localizedDescription
        }
    }

    private func runDestructiveAction() {
        do {
            switch destructiveAction {
            case .deleteData:
                try BackupService.deleteUserData(from: context)
            case .deleteFinance:
                try BackupService.deleteFinanceData(from: context)
            case .deleteTraining:
                try BackupService.deleteTrainingData()
                workouts.reset()
            case .deleteChallenges:
                try BackupService.deleteChallengeData(from: context)
            case .resetApp:
                try BackupService.resetApp(from: context)
                workouts.reset()
                ExerciseImageStore.removeAll()
                defaultTradeFeeCents = TradeFeePreference.defaultCents
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

}

struct FinanceImportSettings: View {
    @ObservedObject var viewModel: DataImportViewModel
    @Binding var importingBank: Bool
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query private var entries: [LedgerEntry]

    var body: some View {
        Section {
            Picker(L("Zielkonto", "Destination account"), selection: $viewModel.destination) {
                Text(L("Auswählen", "Select")).tag(Optional<BankImportDestination>.none)
                Text(L("Neues separates Girokonto", "New separate checking account")).tag(Optional(BankImportDestination.separateChecking))
                ForEach(accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }) { account in
                    Text(account.name).tag(Optional(BankImportDestination.account(account.id)))
                }
            }
            Button {
                importingBank = true
            } label: {
                Label(L("CSV oder CAMT importieren", "Import CSV or CAMT"), systemImage: "square.and.arrow.down")
            }
            if viewModel.pendingBank != nil {
                Text(L(
                    "Wie hoch ist der aktuelle Kontostand auf diesem Konto?",
                    "What is the current balance on this account?"
                ))
                .font(.headline)
                TextField(L("Aktueller Kontostand", "Current balance"), text: $viewModel.currentBalanceText)
                    .keyboardType(.decimalPad)
                Button(L("Import abschließen", "Finish import")) {
                    viewModel.commitPendingBank(context: context, existingEntries: entries)
                }
                .disabled(Money.cents(from: viewModel.currentBalanceText) == nil)
                Button(L("Abbrechen", "Cancel"), role: .cancel) {
                    viewModel.cancelPendingBank()
                }
            }
            Text(L(
                "CSV oder CAMT aufs gewählte Konto. Tage, deren Anzahl schon stimmt, werden übersprungen. Am letzten Buchungstag und bei fehlenden Zeilen kannst du übernehmen. Du gibst den aktuellen Kontostand an.",
                "CSV or CAMT onto the chosen account. Days whose count already matches are skipped. On the last booking day and for missing rows you can import. You enter the current balance."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(L("Bankimport", "Bank import"))
        }
        .appGlassRow()
        .fileImporter(
            isPresented: $importingBank,
            allowedContentTypes: [.commaSeparatedText, .xml, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.importBankFile(from: url, context: context, existingEntries: entries)
            } else if case let .failure(error) = result {
                viewModel.message = error.localizedDescription
            }
        }
    }
}

enum DestructiveAction {
    case deleteFinance
    case deleteTraining
    case deleteChallenges
    case deleteData
    case resetApp

    var title: String {
        switch self {
        case .deleteFinance: L("Finanzen löschen?", "Delete finance?")
        case .deleteTraining: L("Training löschen?", "Delete training?")
        case .deleteChallenges: L("Challenges löschen?", "Delete challenges?")
        case .deleteData: L("Alle Daten löschen?", "Delete all data?")
        case .resetApp: L("App vollständig zurücksetzen?", "Reset the entire app?")
        }
    }

    var message: String {
        switch self {
        case .deleteFinance:
            L(
                "Buchungen, Budgets, Prognosen, Einkäufe, Schulden, Depot und Pools werden gelöscht. Konten, Challenges, Kalender und Trainings bleiben.",
                "Transactions, budgets, forecasts, shopping, debts, holdings, and pools will be deleted. Accounts, challenges, calendar, and training remain."
            )
        case .deleteTraining:
            L(
                "Trainingspläne, Einheiten, Mahlzeiten und die Verknüpfungen zu Challenges werden gelöscht. Challenges, Kalender und Finanzen bleiben.",
                "Workout plans, sessions, meals, and the links to challenges will be deleted. Challenges, calendar, and finance remain."
            )
        case .deleteChallenges:
            L(
                "Challenges, Kalender, Shop, Coins und die Verknüpfungen zu Trainings werden gelöscht. Streak-Multiplikatoren, der Freeze-Faktor und die Abstinenz-Boni gehen auf die Standardwerte zurück. Trainingspläne und Finanzen bleiben.",
                "Challenges, calendar, shop, coins, and the links to workouts will be deleted. Streak multipliers, the freeze factor, and the abstinence bonuses return to their defaults. Workout plans and finance remain."
            )
        case .deleteData:
            L(
                "Buchungen, Budgets, Challenges und weitere Inhalte werden gelöscht. Streak-Multiplikatoren, der Freeze-Faktor und die Abstinenz-Boni gehen auf die Standardwerte zurück. Konten, Sprache und Erscheinungsbild bleiben.",
                "Transactions, budgets, challenges, and other content will be deleted. Streak multipliers, the freeze factor, and the abstinence bonuses return to their defaults. Accounts, language, and appearance remain."
            )
        case .resetApp:
            L(
                "Auch Konten, Trainingsdaten und Einstellungen werden gelöscht. Danach beginnt die Ersteinrichtung erneut.",
                "Accounts, workout data, and settings will also be deleted. Initial setup starts again afterward."
            )
        }
    }
}
