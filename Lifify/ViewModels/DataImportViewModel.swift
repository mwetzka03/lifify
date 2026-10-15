import Combine
import Foundation
import SwiftData

@MainActor
final class DataImportViewModel: ObservableObject {
    @Published var destination: BankImportDestination?
    @Published var message: String?

    func importBankFile(
        from url: URL,
        context: ModelContext,
        existingEntries: [LedgerEntry]
    ) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard let destination else {
                message = L("Bitte zuerst ein Zielkonto auswählen.", "Select a destination account first.")
                return
            }
            let document = try BankImportService.parseDocument(data: data, fileExtension: url.pathExtension)
            let target = destination
            let known = Set(existingEntries.compactMap(\.importFingerprint))
            let result = try BankImportApplier.apply(
                document: document,
                to: target,
                openingBalanceCents: nil,
                context: context
            )
            for row in document.rows where row.amountCents > 0 && row.trade == nil {
                let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
                guard known.isDisjoint(with: fingerprints),
                      let entryID = result.entryIDs[row.fingerprint],
                      let forecastID = IncomeAssignmentStore.forecastID(for: row.senderIBAN)
                else { continue }
                IncomeAssignmentStore.assign(entryID: entryID, to: forecastID)
            }
            message = importMessage(for: result)
        } catch {
            message = error.localizedDescription
        }
    }

    func importTradeRepublic(
        from url: URL,
        context: ModelContext,
        existingEntries: [LedgerEntry]
    ) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let document = try BankImportService.parseTradeRepublic(data: data)
            let known = Set(existingEntries.compactMap(\.importFingerprint))
            let result = try BankImportApplier.apply(
                document: document,
                to: .separateChecking,
                openingBalanceCents: nil,
                context: context
            )
            for row in document.rows where row.amountCents > 0 && row.trade == nil {
                let fingerprints = [row.fingerprint, row.legacyFingerprint].compactMap { $0 }
                guard known.isDisjoint(with: fingerprints),
                      let entryID = result.entryIDs[row.fingerprint],
                      let forecastID = IncomeAssignmentStore.forecastID(for: row.senderIBAN)
                else { continue }
                IncomeAssignmentStore.assign(entryID: entryID, to: forecastID)
            }
            message = importMessage(for: result)
        } catch {
            message = error.localizedDescription
        }
    }

    private func importMessage(for result: BankImportResult) -> String {
        var parts: [String] = []
        if result.createdSeparateChecking {
            parts.append(String(
                format: L("Separates Girokonto „%@“ angelegt.", "Created the separate checking account “%@”."),
                result.accountName
            ))
        } else {
            parts.append(String(
                format: L("Auf „%@“ gebucht.", "Booked to “%@”."),
                result.accountName
            ))
        }
        parts.append(String(
            format: L("%d Buchungen importiert.", "%d transactions imported."),
            result.importedCount
        ))
        if result.holdingCount > 0 {
            parts.append(String(
                format: L("%d Depotpositionen übernommen.", "%d portfolio positions imported."),
                result.holdingCount
            ))
        }
        if result.skippedBeforeStart > 0 {
            parts.append(L(
                "Buchungen vor dem Start des ersten Zeitraums wurden nicht angelegt. Spätere Buchungen sind dabei. Der Startsaldo kommt aus der Saldo-Spalte.",
                "Transactions before the start of the first period were not booked. Later transactions are included. The opening balance comes from the balance column."
            ))
        }
        return parts.joined(separator: " ")
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
