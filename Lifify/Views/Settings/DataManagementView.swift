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
    @Query private var articles: [SavedArticle]
    @StateObject private var viewModel = DataImportViewModel()
    @State private var importingBank = false
    @State private var importingBackup = false
    @State private var exportingBackup = false
    @State private var backupDocument = BackupDocument()

    var body: some View {
        Form {
            Section {
                Picker(L("Zielkonto", "Destination account"), selection: $viewModel.selectedAccountID) {
                    Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                    ForEach(accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Button {
                    importingBank = true
                } label: {
                    Label(L("CSV oder einzelne CAMT-Datei importieren", "Import CSV or one CAMT file"), systemImage: "square.and.arrow.down")
                }
                Text(L(
                    "Unterstützt CSV und eine CAMT-XML-Datei. ZIP und MT940 werden nicht verarbeitet.",
                    "Supports CSV and one CAMT XML file. ZIP and MT940 are not processed."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text(L("Bankimport", "Bank import"))
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
                articles: articles
            ))
            exportingBackup = true
        } catch {
            viewModel.message = error.localizedDescription
        }
    }
}
