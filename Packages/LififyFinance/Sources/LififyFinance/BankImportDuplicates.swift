import Foundation
import LififyCore

/// Settings import: skip older days that already have the same number of bookings.
/// Ask about the last booking day, and about days where the file has extra rows.
public enum BankImportDuplicates {
    public struct Plan {
        public var skip: Set<String> = []
        public var reviewByFingerprint: [String: ImportSimilarChoice] = [:]

        public func shouldSkip(_ fingerprint: String) -> Bool {
            skip.contains(fingerprint)
        }

        public func reviewChoice(for fingerprint: String) -> ImportSimilarChoice? {
            reviewByFingerprint[fingerprint]
        }

        public init(skip: Set<String> = [], reviewByFingerprint: [String: ImportSimilarChoice] = [:]) {
            self.skip = skip
            self.reviewByFingerprint = reviewByFingerprint
        }
    }

    public enum Action: Equatable {
        case skip
        case ingest
        case review(include: Bool)
    }

    /// `day` and `lastExistingDay` are start-of-day values.
    public static func action(
        day: Date,
        lastExistingDay: Date?,
        existingCount: Int,
        importCount: Int,
        identical: Bool,
        matchedExisting: Bool
    ) -> Action {
        if identical { return .skip }
        guard let last = lastExistingDay else { return .ingest }
        if day > last { return .ingest }
        if matchedExisting {
            return day == last ? .review(include: false) : .skip
        }
        if day == last { return .review(include: true) }
        if existingCount < importCount { return .review(include: true) }
        return .skip
    }

    public static func plan(
        rows: [ImportedTransaction],
        entries: [LedgerEntry],
        accountID: UUID,
        calendar: Calendar = .current
    ) -> Plan {
        func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        let cashRows = rows.filter { $0.trade == nil }
        let existing = entries.filter { entry in
            entry.kind != .adjustment
                && (entry.accountID == accountID
                    || entry.fromAccountID == accountID
                    || entry.toAccountID == accountID)
        }
        let lastDay = existing.map { day($0.date) }.max()
        var existingByDay: [Date: [LedgerEntry]] = [:]
        for entry in existing {
            existingByDay[day(entry.date), default: []].append(entry)
        }
        var importByDay: [Date: [ImportedTransaction]] = [:]
        for row in cashRows {
            importByDay[day(row.date), default: []].append(row)
        }
        var plan = Plan()
        for (date, dayRows) in importByDay {
            var unused = existingByDay[date] ?? []
            let existingCount = unused.count
            let importCount = dayRows.count
            for row in dayRows {
                if let index = unused.firstIndex(where: { isIdentical($0, row: row) }) {
                    unused.remove(at: index)
                    plan.skip.insert(row.fingerprint)
                    continue
                }
                if let index = unused.firstIndex(where: { isSimilar($0, row: row) }) {
                    let match = unused.remove(at: index)
                    switch action(
                        day: date,
                        lastExistingDay: lastDay,
                        existingCount: existingCount,
                        importCount: importCount,
                        identical: false,
                        matchedExisting: true
                    ) {
                    case .skip:
                        plan.skip.insert(row.fingerprint)
                    case .ingest:
                        break
                    case .review(let include):
                        plan.reviewByFingerprint[row.fingerprint] = choice(
                            row: row,
                            existing: match,
                            accountID: accountID,
                            include: include,
                            isExtra: false
                        )
                    }
                    continue
                }
                switch action(
                    day: date,
                    lastExistingDay: lastDay,
                    existingCount: existingCount,
                    importCount: importCount,
                    identical: false,
                    matchedExisting: false
                ) {
                case .skip:
                    plan.skip.insert(row.fingerprint)
                case .ingest:
                    break
                case .review(let include):
                    plan.reviewByFingerprint[row.fingerprint] = extraChoice(
                        row: row,
                        leftover: unused.first,
                        accountID: accountID,
                        include: include,
                        existingCount: existingCount
                    )
                }
            }
        }
        return plan
    }

    private static func isIdentical(_ entry: LedgerEntry, row: ImportedTransaction) -> Bool {
        if entry.importFingerprint == row.fingerprint { return true }
        if let legacy = row.legacyFingerprint, entry.importFingerprint == legacy {
            let purpose = BankImportService.purposeMark(notes: row.notes)
            return purpose.isEmpty || entry.notes.contains(purpose)
        }
        return false
    }

    private static func isSimilar(_ entry: LedgerEntry, row: ImportedTransaction) -> Bool {
        guard entry.kind != .adjustment else { return false }
        guard abs(entry.amountCents) == abs(row.amountCents) else { return false }
        guard payeesMatch(row.title, entry.title) else { return false }
        let purpose = BankImportService.purposeMark(notes: row.notes)
        if !purpose.isEmpty, !entry.notes.contains(purpose) { return false }
        return true
    }

    private static func payeesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = payeeKey(lhs)
        let right = payeeKey(rhs)
        guard left.count >= 4, right.count >= 4 else { return false }
        if left == right { return true }
        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        return shorter.count >= 8 && longer.hasPrefix(shorter)
    }

    private static func payeeKey(_ title: String) -> String {
        let head = title.split(whereSeparator: { $0 == "/" || $0 == "|" }).first.map(String.init) ?? title
        let folded = head.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }

    private static func choice(
        row: ImportedTransaction,
        existing: LedgerEntry,
        accountID: UUID,
        include: Bool,
        isExtra: Bool
    ) -> ImportSimilarChoice {
        ImportSimilarChoice(
            id: UUID(),
            fingerprint: row.fingerprint,
            date: row.date,
            title: row.title,
            notes: row.notes,
            signedAmountCents: row.amountCents,
            accountID: accountID,
            existingTitle: existing.title,
            existingDate: existing.date,
            existingAmountCents: existing.amountCents,
            include: include,
            isExtra: isExtra
        )
    }

    private static func extraChoice(
        row: ImportedTransaction,
        leftover: LedgerEntry?,
        accountID: UUID,
        include: Bool,
        existingCount: Int
    ) -> ImportSimilarChoice {
        let title = leftover?.title ?? L(
            "\(existingCount) Buchungen an diesem Tag",
            "\(existingCount) bookings on this day"
        )
        return ImportSimilarChoice(
            id: UUID(),
            fingerprint: row.fingerprint,
            date: row.date,
            title: row.title,
            notes: row.notes,
            signedAmountCents: row.amountCents,
            accountID: accountID,
            existingTitle: title,
            existingDate: leftover?.date ?? row.date,
            existingAmountCents: leftover?.amountCents ?? 0,
            include: include,
            isExtra: true
        )
    }
}
