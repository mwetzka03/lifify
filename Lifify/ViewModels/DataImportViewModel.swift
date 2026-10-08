import Foundation
import SwiftData

@MainActor
final class DataImportViewModel: ObservableObject {
    @Published var selectedAccountID: UUID?
    @Published var message: String?

    func importBankFile(
        from url: URL,
        context: ModelContext,
        existingEntries: [LedgerEntry]
    ) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let accountID = selectedAccountID else {
                message = L("Bitte zuerst ein Zielkonto auswählen.", "Select a destination account first.")
                return
            }
            let data = try Data(contentsOf: url)
            let rows = try BankImportService.parse(data: data, fileExtension: url.pathExtension)
            let known = Set(existingEntries.compactMap(\.importFingerprint))
            var imported = 0
            for row in rows where !known.contains(row.fingerprint) {
                let kind: LedgerKind = row.amountCents < 0 ? .expense : .income
                context.insert(LedgerEntry(
                    date: row.date,
                    title: row.title,
                    notes: row.notes,
                    amountCents: row.amountCents,
                    kind: kind,
                    accountID: accountID,
                    importFingerprint: row.fingerprint
                ))
                imported += 1
            }
            try context.save()
            message = String(format: L("%d Buchungen importiert.", "%d transactions imported."), imported)
        } catch {
            message = error.localizedDescription
        }
    }

    func restoreBackup(from url: URL, context: ModelContext) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try BackupService.restore(data: Data(contentsOf: url), into: context)
            message = L("Sicherung erfolgreich wiederhergestellt.", "Backup restored successfully.")
        } catch {
            message = error.localizedDescription
        }
    }
}
