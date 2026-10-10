import Combine
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
            var known = Set(existingEntries.compactMap(\.importFingerprint))
            var imported = 0
            for row in rows {
                let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
                guard known.isDisjoint(with: fingerprints) else { continue }
                let kind: LedgerKind = row.amountCents < 0 ? .expense : .income
                let entry = LedgerEntry(
                    date: row.date,
                    title: row.title,
                    notes: row.notes,
                    amountCents: row.amountCents,
                    kind: kind,
                    accountID: accountID,
                    importFingerprint: row.fingerprint
                )
                context.insert(entry)
                if row.amountCents > 0,
                   let forecastID = IncomeAssignmentStore.forecastID(for: row.senderIBAN) {
                    IncomeAssignmentStore.assign(entryID: entry.id, to: forecastID)
                }
                known.formUnion(fingerprints)
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
            let accounts = try context.fetch(FetchDescriptor<Account>())
            if accounts.contains(where: \.isMain) {
                message = L("Sicherung erfolgreich wiederhergestellt.", "Backup restored successfully.")
            } else {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(false, forKey: "onboardingInProgress")
                UserDefaults.standard.set(4, forKey: "onboardingStep")
                message = L(
                    "Die Sicherung enthält kein Hauptkonto. Die Einrichtung wird fortgesetzt.",
                    "The backup contains no main account. Setup will continue."
                )
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
