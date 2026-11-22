import Foundation
import SwiftData

enum NoticeTemplateAction: String, Codable, CaseIterable, Equatable, Hashable {
    case expense
    case income
    case transferIn
    case transferOut

    var label: String {
        switch self {
        case .expense: L("Ausgabe", "Expense")
        case .income: L("Einnahme", "Income")
        case .transferIn: L("Umbuchung auf dieses Konto", "Transfer onto this account")
        case .transferOut: L("Umbuchung von diesem Konto", "Transfer from this account")
        }
    }
}

struct NoticeTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var accountID: UUID
    var name: String
    var example: String
    var action: NoticeTemplateAction
    var counterpartyAccountID: UUID?

    init(
        id: UUID = UUID(),
        accountID: UUID,
        name: String,
        example: String,
        action: NoticeTemplateAction,
        counterpartyAccountID: UUID? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.example = example
        self.action = action
        self.counterpartyAccountID = counterpartyAccountID
    }

    func matches(_ text: String) -> Bool {
        let needed = Self.markers(in: example)
        guard !needed.isEmpty else { return false }
        let folded = Self.folded(text)
        return needed.allSatisfy { marker in
            folded.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: marker))\\b",
                options: .regularExpression
            ) != nil
        }
    }

    static func markers(in text: String) -> [String] {
        let folded = folded(text)
        return markerWords.filter { word in
            folded.range(
                of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                options: .regularExpression
            ) != nil
        }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    private static let markerWords = [
        "abbuchung", "lastschrift", "kartenzahlung", "ausgegeben", "ausgabe", "bezahlt", "paid", "payment",
        "sent", "kauf", "buy", "withdrawal", "auszahlung", "spent", "debit", "belastung",
        "gutschrift", "eingang", "erhalten", "received", "einzahlung", "dividende", "dividend",
        "verkauf", "sell", "credit", "gutgeschrieben", "incoming", "erstattung", "refund",
        "uberweisung", "echtzeit", "paypal", "visa", "kontowecker"
    ]
}

@MainActor
enum NoticeTemplateStore {
    static let backupType = "noticeTemplate"
    private static var cached: [NoticeTemplate]?

    static func clearCache() {
        cached = nil
    }

    static func all() -> [NoticeTemplate] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredNoticeTemplate>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.compactMap { try? JSONDecoder().decode(NoticeTemplate.self, from: $0.payload) }
        cached = decoded
        return decoded
    }

    static func save(_ templates: [NoticeTemplate]) {
        if let context = LififyDatabase.sideContext {
            ((try? context.fetch(FetchDescriptor<StoredNoticeTemplate>())) ?? []).forEach(context.delete)
            for (position, template) in templates.enumerated() {
                guard let payload = try? JSONEncoder().encode(template) else { continue }
                context.insert(StoredNoticeTemplate(payload: payload, position: position))
            }
            LififyDatabase.saveSide()
        }
        cached = templates
    }

    static func exportRecords() -> [BackupRecord] {
        all().compactMap { template in
            guard let data = try? JSONEncoder().encode(template) else { return nil }
            return BackupRecord(type: backupType, id: UUID(), strings: [String(decoding: data, as: UTF8.self)])
        }
    }

    static func restore(_ record: BackupRecord) {
        guard let text = record.strings.first,
              let value = try? JSONDecoder().decode(NoticeTemplate.self, from: Data(text.utf8))
        else { return }
        save(all() + [value])
    }

    static func matching(text: String, accountID: UUID, in templates: [NoticeTemplate]) -> NoticeTemplate? {
        templates
            .filter { $0.accountID == accountID && $0.matches(text) }
            .max { NoticeTemplate.markers(in: $0.example).count < NoticeTemplate.markers(in: $1.example).count }
    }

    static func reset() {
        save([])
    }
}
