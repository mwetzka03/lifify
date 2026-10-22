import Foundation

enum ExternalIncome {
    static func countsInCombinedFinance(_ entry: LedgerEntry, accounts: [Account]) -> Bool {
        if isDividendOrInterest(entry) { return true }
        return !isFromOwnIBAN(entry, accounts: accounts)
    }

    static func countsInHomeBudget(_ entry: LedgerEntry, accounts: [Account]) -> Bool {
        if isDividendOrInterest(entry) { return false }
        return !isFromOwnIBAN(entry, accounts: accounts)
    }

    static func isDividendOrInterest(_ entry: LedgerEntry) -> Bool {
        let notes = entry.notes.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        return notes.contains("typ: ertrag")
            || notes.contains("type: ertrag")
            || notes.contains("typ: zinsen")
            || notes.contains("type: zinsen")
            || notes.contains("type: dividend")
            || notes.contains("type: interest")
    }

    static func isFromOwnIBAN(_ entry: LedgerEntry, accounts: [Account]) -> Bool {
        let own = Set(
            accounts
                .map { $0.iban.replacingOccurrences(of: " ", with: "").uppercased() }
                .filter { !$0.isEmpty }
        )
        guard !own.isEmpty else { return false }
        let parsed = BankImportService.ibans(from: entry.notes, amountCents: abs(entry.amountCents))
        return !parsed.sender.isEmpty && own.contains(parsed.sender)
    }
}

@MainActor
enum PortfolioCashFlow {
    struct Line: Identifiable {
        var id: String
        var entry: LedgerEntry
        var title: String
        var signedCents: Int
        var counts: Bool
        var caption: String?
    }

    static func isSecurityPurchase(_ entry: LedgerEntry, portfolioIDs: Set<UUID>) -> Bool {
        guard entry.kind == .transfer, let to = entry.toAccountID, portfolioIDs.contains(to) else { return false }
        if let from = entry.fromAccountID, portfolioIDs.contains(from) { return false }
        return true
    }

    static func lines(
        kind: LedgerKind,
        entries: [LedgerEntry],
        accounts: [Account],
        holdings: [PortfolioHolding],
        period: ForecastPeriod?,
        account: Account?
    ) -> [Line] {
        guard kind == .income || kind == .expense else { return [] }
        let portfolios = Set(accounts.filter { $0.kind == .portfolio }.map(\.id))
        let known = Set(accounts.map(\.id))
        var lines: [Line] = []
        for entry in entries where entry.kind == .transfer {
            if let period, !period.contains(entry.date) { continue }
            guard let from = entry.fromAccountID, let to = entry.toAccountID else { continue }
            guard known.isEmpty || known.contains(from) || known.contains(to) else { continue }
            let fromPortfolio = portfolios.contains(from)
            let toPortfolio = portfolios.contains(to)
            let security = fromPortfolio != toPortfolio
            if let account {
                appendAccountLine(
                    kind: kind,
                    entry: entry,
                    account: account,
                    from: from,
                    to: to,
                    security: security,
                    fromPortfolio: fromPortfolio,
                    toPortfolio: toPortfolio,
                    lines: &lines
                )
            } else if security {
                appendCombinedSecurityLine(kind: kind, entry: entry, fromPortfolio: fromPortfolio, holdings: holdings, lines: &lines)
            }
        }
        return lines
    }

    static func countedCents(
        kind: LedgerKind,
        entries: [LedgerEntry],
        accounts: [Account],
        holdings: [PortfolioHolding],
        period: ForecastPeriod?,
        account: Account?
    ) -> Int {
        lines(
            kind: kind,
            entries: entries,
            accounts: accounts,
            holdings: holdings,
            period: period,
            account: account
        )
        .filter(\.counts)
        .reduce(0) { $0 + abs($1.signedCents) }
    }

    private static func appendAccountLine(
        kind: LedgerKind,
        entry: LedgerEntry,
        account: Account,
        from: UUID,
        to: UUID,
        security: Bool,
        fromPortfolio: Bool,
        toPortfolio: Bool,
        lines: inout [Line]
    ) {
        let amount = abs(entry.amountCents)
        if security {
            if kind == .expense, from == account.id, toPortfolio {
                lines.append(plain(entry, signed: -amount, counts: true))
            } else if kind == .income, to == account.id, fromPortfolio {
                lines.append(plain(entry, signed: amount, counts: true))
            }
            return
        }
        if kind == .expense, from == account.id {
            lines.append(plain(entry, signed: -amount, counts: true))
        } else if kind == .income, to == account.id {
            lines.append(plain(entry, signed: amount, counts: true))
        }
    }

    private static func appendCombinedSecurityLine(
        kind: LedgerKind,
        entry: LedgerEntry,
        fromPortfolio: Bool,
        holdings: [PortfolioHolding],
        lines: inout [Line]
    ) {
        guard fromPortfolio, let gain = HoldingMaintenance.realizedGainCents(for: entry, holdings: holdings), gain != 0 else { return }
        if gain > 0, kind == .income {
            lines.append(Line(
                id: "pnl-\(entry.id.uuidString)",
                entry: entry,
                title: entry.title,
                signedCents: gain,
                counts: true,
                caption: L("Kursdifferenz", "Price difference")
            ))
        } else if gain < 0, kind == .expense {
            lines.append(Line(
                id: "pnl-\(entry.id.uuidString)",
                entry: entry,
                title: entry.title,
                signedCents: gain,
                counts: true,
                caption: L("Kursdifferenz", "Price difference")
            ))
        }
    }

    private static func plain(_ entry: LedgerEntry, signed: Int, counts: Bool) -> Line {
        Line(id: entry.id.uuidString, entry: entry, title: entry.title, signedCents: signed, counts: counts, caption: nil)
    }
}
