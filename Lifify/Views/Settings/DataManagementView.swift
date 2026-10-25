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
    @State private var importingBank = false
    @State private var importingTradeRepublic = false
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
                Text(L(
                    "Das Zielkonto gilt nur für CSV und CAMT. Ein PDF wird hier nicht gelesen.",
                    "The destination account is only for CSV and CAMT. A PDF is not read here."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Bankimport", "Bank import"))
            }

            Section {
                Button {
                    importingTradeRepublic = true
                } label: {
                    Label(L("Kontoauszug hochladen", "Upload statement"), systemImage: "doc.badge.plus")
                }
                Text(L(
                    "Nur die Umsatzübersicht. Das Girokonto wird über die IBAN wiederverwendet oder neu angelegt, das Depot hängt daran. Buchungen vor dem Start des ersten Zeitraums vom Hauptkonto werden nicht angelegt, spätere schon. Die Depotstände aus dem ganzen Auszug werden übernommen. Der Startsaldo ist der Saldo am Starttag, sonst vom letzten Tag davor.",
                    "Only the transaction overview. The checking account is reused by IBAN or created, and the portfolio is linked to it. Transactions before the start of the main account’s first period are not booked; later ones are. Portfolio positions from the whole statement are imported. The opening balance is the balance on the start day, or the previous day."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Trade Republic")
            }

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
                    Label(L("Training exportieren", "Export training"), systemImage: "figure.strengthtraining.traditional")
                }
                Button {
                    importingBackup = true
                } label: {
                    Label(L("Sicherung wiederherstellen", "Restore backup"), systemImage: "arrow.clockwise.icloud")
                }
                Text(L(
                    "Eine Teilsicherung ersetzt nur diesen Bereich. Verknüpfungen zwischen Challenges und Trainings liegen in beiden Sicherungen. Eine volle Sicherung ersetzt alles.",
                    "A partial backup replaces only that area. Links between challenges and workouts are stored in both backups. A full backup replaces everything."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

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
        }
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
        .fileImporter(
            isPresented: $importingTradeRepublic,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.importTradeRepublic(from: url, context: context, existingEntries: entries)
            } else if case let .failure(error) = result {
                viewModel.message = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $importingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                viewModel.restoreBackup(from: url, context: context)
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
        .sheet(item: $viewModel.review) { review in
            ImportReviewSheet(review: review) { updated in
                do {
                    try BankImportApplier.commitReview(updated, context: context)
                } catch {
                    viewModel.message = error.localizedDescription
                }
            }
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
            exportFilename = "\(exportPrefix(scope))-\(Date.now.dayKey)"
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

    private func exportPrefix(_ scope: BackupScope) -> String {
        switch scope {
        case .all: "Lifify"
        case .finance: "Lifify-Finanzen"
        case .challenges: "Lifify-Challenges"
        case .training: "Lifify-Training"
        }
    }
}

private enum DestructiveAction {
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
                "Challenges, Kalender, Shop, Coins und die Verknüpfungen zu Trainings werden gelöscht. Trainingspläne und Finanzen bleiben.",
                "Challenges, calendar, shop, coins, and the links to workouts will be deleted. Workout plans and finance remain."
            )
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
