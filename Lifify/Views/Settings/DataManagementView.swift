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
    @State private var importingBackup = false
    @State private var exportingBackup = false
    @State private var backupDocument = BackupDocument()

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
                    "Nur die Umsatzübersicht. Das Girokonto wird über die IBAN wiederverwendet oder neu angelegt, das Depot hängt daran. Buchungen außerhalb des ersten Zeitraums vom Hauptkonto werden nicht angelegt, die Depotstände schon. Der Startsaldo ist der Saldo am Starttag, sonst vom letzten Tag davor.",
                    "Only the transaction overview. The checking account is reused by IBAN or created, and the portfolio is linked to it. Transactions outside the main account’s first period are not booked; the portfolio positions are. The opening balance is the balance on the start day, or the previous day."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Trade Republic")
            }

            Section(L("JSON-Sicherung", "JSON backup")) {
                Button {
                    createBackup()
                } label: {
                    Label(L("Sicherung exportieren", "Export backup"), systemImage: "square.and.arrow.up")
                }
                Button {
                    importingBackup = true
                } label: {
                    Label(L("Sicherung wiederherstellen", "Restore backup"), systemImage: "arrow.clockwise.icloud")
                }
                Text(L(
                    "Wiederherstellen ersetzt alle derzeitigen Lifify-Daten.",
                    "Restoring replaces all current Lifify data."
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
            defaultFilename: "Lifify-\(Date.now.dayKey)"
        ) { result in
            if case let .failure(error) = result { viewModel.message = error.localizedDescription }
        }
        .alert(L("Lifify", "Lifify"), isPresented: Binding(
            get: { viewModel.message != nil },
            set: { if !$0 { viewModel.message = nil } }
        )) {
            Button("OK") { viewModel.message = nil }
        } message: {
            Text(viewModel.message ?? "")
        }
    }

    private func createBackup() {
        do {
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
                bucketItems: bucketItems
            ))
            exportingBackup = true
        } catch {
            viewModel.message = error.localizedDescription
        }
    }
}
