import Foundation

enum PortfolioCashFlow {
    struct Line: Identifiable {
        var id: String
        var entry: LedgerEntry
        var signedCents: Int
        var counts: Bool
    }

    static func lines(
        kind: LedgerKind,
        entries: [LedgerEntry],
        accounts: [Account],
        period: ForecastPeriod?,
        account: Account?
    ) -> [Line] {
        guard kind == .income || kind == .expense else { return [] }
        let portfolioIDs = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        var lines: [Line] = []
        for entry in entries where entry.kind == .transfer {
            if let period, !period.contains(entry.date) { continue }
            let fromPortfolio = entry.fromAccountID.map { portfolioIDs.contains($0) } ?? false
            let toPortfolio = entry.toAccountID.map { portfolioIDs.contains($0) } ?? false
            guard fromPortfolio != toPortfolio else { continue }
            let amount = abs(entry.amountCents)
            if let account {
                if kind == .expense, entry.fromAccountID == account.id {
                    lines.append(Line(id: entry.id.uuidString, entry: entry, signedCents: -amount, counts: true))
                } else if kind == .income, entry.toAccountID == account.id {
                    lines.append(Line(id: entry.id.uuidString, entry: entry, signedCents: amount, counts: true))
                }
            } else if kind == .expense {
                lines.append(Line(id: entry.id.uuidString, entry: entry, signedCents: -amount, counts: false))
            } else {
                lines.append(Line(id: entry.id.uuidString, entry: entry, signedCents: amount, counts: false))
            }
        }
        return lines
    }

    static func countedCents(
        kind: LedgerKind,
        entries: [LedgerEntry],
        accounts: [Account],
        period: ForecastPeriod?,
        account: Account?
    ) -> Int {
        lines(kind: kind, entries: entries, accounts: accounts, period: period, account: account)
            .filter(\.counts)
            .reduce(0) { $0 + abs($1.signedCents) }
    }
}
