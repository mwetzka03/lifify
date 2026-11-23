import Foundation
import LififyCore
import SwiftData

public enum NoticeTemplateAction: String, Codable, CaseIterable, Equatable, Hashable {
    case expense
    case income
    case transferIn
    case transferOut
    case depotBuy
    case depotSale
    case ignore

    public var label: String {
        switch self {
        case .expense: L("Ausgabe", "Expense")
        case .income: L("Einnahme", "Income")
        case .transferIn: L("Umbuchung auf dieses Konto", "Transfer onto this account")
        case .transferOut: L("Umbuchung von diesem Konto", "Transfer from this account")
        case .depotBuy: L("Depotkauf", "Portfolio buy")
        case .depotSale: L("Depotverkauf", "Portfolio sale")
        case .ignore: L("Nicht buchen", "Do not book")
        }
    }
}

public struct NoticeTemplate: Identifiable, Codable, Equatable {
    public var id: UUID
    public var accountID: UUID
    public var name: String
    public var example: String
    public var action: NoticeTemplateAction
    public var counterpartyAccountID: UUID?
    public var isEnabled: Bool
    /// Set for a built-in layout. Such a template reads the notice with that layout's own rules.
    public var format: NoticeFormat?

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        name: String,
        example: String,
        action: NoticeTemplateAction,
        counterpartyAccountID: UUID? = nil,
        isEnabled: Bool = true,
        format: NoticeFormat? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.example = example
        self.action = action
        self.counterpartyAccountID = counterpartyAccountID
        self.isEnabled = isEnabled
        self.format = format
    }

    private enum CodingKeys: String, CodingKey {
        case id, accountID, name, example, action, counterpartyAccountID, isEnabled, format
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        accountID = try box.decode(UUID.self, forKey: .accountID)
        name = try box.decode(String.self, forKey: .name)
        example = try box.decode(String.self, forKey: .example)
        action = try box.decode(NoticeTemplateAction.self, forKey: .action)
        counterpartyAccountID = try box.decodeIfPresent(UUID.self, forKey: .counterpartyAccountID)
        isEnabled = try box.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        format = try box.decodeIfPresent(NoticeFormat.self, forKey: .format)
    }

    public func matches(_ text: String) -> Bool {
        if let format { return format.matches(text) }
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

    public static func markers(in text: String) -> [String] {
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
public enum NoticeTemplateStore {
    public static let backupType = "noticeTemplate"
    private static var cached: [NoticeTemplate]?

    public static func clearCache() {
        cached = nil
    }

    public static func all() -> [NoticeTemplate] {
        if let cached { return cached }
        let rows = LififyDatabase.rows(FetchDescriptor<StoredNoticeTemplate>(sortBy: [SortDescriptor(\.position)]))
        let decoded = rows.compactMap { try? JSONDecoder().decode(NoticeTemplate.self, from: $0.payload) }
        cached = decoded
        return decoded
    }

    public static func save(_ templates: [NoticeTemplate]) {
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

    public static func exportRecords() -> [BackupRecord] {
        all().compactMap { template in
            guard let data = try? JSONEncoder().encode(template) else { return nil }
            return BackupRecord(type: backupType, id: UUID(), strings: [String(decoding: data, as: UTF8.self)])
        }
    }

    public static func restore(_ record: BackupRecord) {
        guard let text = record.strings.first,
              let value = try? JSONDecoder().decode(NoticeTemplate.self, from: Data(text.utf8))
        else { return }
        save(all() + [value])
    }

    public static func matching(text: String, accountID: UUID, in templates: [NoticeTemplate]) -> NoticeTemplate? {
        let hits = templates.filter { $0.isEnabled && $0.accountID == accountID && $0.matches(text) }
        let own = hits.filter { $0.format == nil }
            .max { NoticeTemplate.markers(in: $0.example).count < NoticeTemplate.markers(in: $1.example).count }
        return own ?? hits.first
    }

    public static func reset() {
        save([])
        LinkTable.clear(.dismissedNoticeTemplates)
    }
}
