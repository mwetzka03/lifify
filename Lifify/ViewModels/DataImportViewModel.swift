import Combine
import Foundation
import SwiftData

@MainActor
final class DataImportViewModel: ObservableObject {
    @Published var destination: BankImportDestination?
    @Published var message: String?
    @Published var review: ImportReview?
    @Published var pendingBank: BankImportDocument?
    @Published var currentBalanceText = ""

    func importBankFile(
        from url: URL,
        context: ModelContext,
        existingEntries: [LedgerEntry]
    ) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard destination != nil else {
                message = L("Bitte zuerst ein Zielkonto auswählen.", "Select a destination account first.")
                return
            }
            let document = try BankImportService.parseDocument(data: data, fileExtension: url.pathExtension)
            guard !document.rows.isEmpty else {
                message = L("Der Export enthält keine Buchungen.", "The export contains no transactions.")
                return
            }
            pendingBank = document
            currentBalanceText = ""
        } catch {
            message = error.localizedDescription
        }
    }

    func commitPendingBank(
        context: ModelContext,
        existingEntries: [LedgerEntry]
    ) {
        guard let document = pendingBank else { return }
        guard let destination else {
            message = L("Bitte zuerst ein Zielkonto auswählen.", "Select a destination account first.")
            return
        }
        guard let current = Money.cents(from: currentBalanceText) else { return }
        let known = Set(existingEntries.compactMap(\.importFingerprint))
        do {
            let result = try BankImportApplier.apply(
                document: document,
                to: destination,
                currentBalanceCents: current,
                detectDuplicates: true,
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
            pendingBank = nil
            currentBalanceText = ""
            message = importMessage(for: result)
            review = result.review.isEmpty ? nil : result.review
        } catch {
            message = error.localizedDescription
        }
    }

    func cancelPendingBank() {
        pendingBank = nil
        currentBalanceText = ""
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
                detectDuplicates: true,
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
            review = result.review.isEmpty ? nil : result.review
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
        if !result.review.isEmpty {
            parts.append(L(
                "Prüfe mögliche Umbuchungen und ähnliche Buchungen.",
                "Review possible transfers and similar transactions."
            ))
        }
        return parts.joined(separator: " ")
    }

    func restoreBackup(from url: URL, context: ModelContext) {
        restoreBackups(from: [url], context: context)
    }

    func restoreBackups(from urls: [URL], context: ModelContext) {
        var accessors: [URL] = []
        defer { accessors.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            var payloads: [Data] = []
            for url in urls {
                if url.startAccessingSecurityScopedResource() { accessors.append(url) }
                payloads.append(try Data(contentsOf: url))
            }
            let scopes = try BackupService.restore(payloads: payloads, into: context)
            let accounts = try context.fetch(FetchDescriptor<Account>())
            if accounts.contains(where: \.isMain) {
                message = BackupService.restoredMessage(scopes)
            } else {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(false, forKey: "onboardingInProgress")
                UserDefaults.standard.set(4, forKey: "onboardingStep")
                message = BackupService.restoredMessage(scopes) + " " + L(
                    "Die Sicherung enthält kein Hauptkonto. Die Einrichtung wird fortgesetzt.",
                    "The backup contains no main account. Setup will continue."
                )
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
