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
        }
        .navigationTitle(L("Import & Sicherung", "Import & backup"))
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

    private func exportPrefix(_ scope: BackupScope) -> String {
        switch scope {
        case .all: "Lifify"
        case .finance: "Lifify-Finanzen"
        case .challenges: "Lifify-Challenges"
        case .training: "Lifify-Training"
        }
    }
}
