import Foundation
import LififyCore

/// A category a person created.
public struct CustomChallengeCategory: Codable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var separate: Bool

    public init(id: UUID, name: String, separate: Bool) {
        self.id = id
        self.name = name
        self.separate = separate
    }
}

/// How the active challenge list is split into headings.
/// Sport and abstinence always stand alone. A custom category does too when it is marked separate.
/// Everything else shares one section.
public enum ChallengeSections {
    /// A challenge, reduced for sectioning.
    public struct Challenge: Equatable {
        public var id: UUID
        public var categoryRaw: String

        public init(id: UUID, categoryRaw: String) {
            self.id = id
            self.categoryRaw = categoryRaw
        }
    }

    /// A custom category, reduced for sectioning.
    public struct Custom: Equatable {
        public var id: UUID
        public var name: String
        public var separate: Bool

        public init(id: UUID, name: String, separate: Bool) {
            self.id = id
            self.name = name
            self.separate = separate
        }
    }

    /// One section of the challenge board.
    public struct Section: Equatable, Identifiable {
        public var id: String
        public var showsTitle: Bool
        public var challengeIDs: [UUID]

        public init(id: String, showsTitle: Bool, challengeIDs: [UUID]) {
            self.id = id
            self.showsTitle = showsTitle
            self.challengeIDs = challengeIDs
        }
    }

    /// Reads a custom category's ID.
    public static func customID(from raw: String) -> UUID? {
        let prefix = "custom:"
        guard raw.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(prefix.count)))
    }

    /// Sorts challenges into their sections.
    public static func make(challenges: [Challenge], customs: [Custom]) -> [Section] {
        var abstinence: [UUID] = []
        var sport: [UUID] = []
        var separate: [UUID: [UUID]] = [:]
        var rest: [UUID] = []
        let separateCustoms = Dictionary(uniqueKeysWithValues: customs.filter(\.separate).map { ($0.id, $0) })
        for challenge in challenges {
            if challenge.categoryRaw == ChallengeCategory.abstinence.rawValue {
                abstinence.append(challenge.id)
            } else if challenge.categoryRaw == ChallengeCategory.sport.rawValue {
                sport.append(challenge.id)
            } else if let customID = customID(from: challenge.categoryRaw), separateCustoms[customID] != nil {
                separate[customID, default: []].append(challenge.id)
            } else {
                rest.append(challenge.id)
            }
        }
        var sections: [Section] = []
        if !abstinence.isEmpty {
            sections.append(Section(id: "abstinence", showsTitle: true, challengeIDs: abstinence))
        }
        if !sport.isEmpty {
            sections.append(Section(id: "sport", showsTitle: true, challengeIDs: sport))
        }
        let ordered = customs.filter(\.separate).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for custom in ordered {
            guard let ids = separate[custom.id], !ids.isEmpty else { continue }
            sections.append(Section(id: custom.id.uuidString, showsTitle: true, challengeIDs: ids))
        }
        if !rest.isEmpty {
            sections.append(Section(id: "rest", showsTitle: !sections.isEmpty, challengeIDs: rest))
        }
        return sections
    }
}

/// Names the user adds beside Sport, Abstinenz and Sonstiges.
@MainActor
public enum ChallengeCategoryStore {
    public static let revisionKey = "lifify.customCategoryRevision"
    private static var cache: [CustomChallengeCategory]?

    /// Drops the in-memory copy.
    public static func clearCache() {
        cache = nil
    }

    /// Builds the stored value of a custom category.
    public static func raw(_ id: UUID) -> String {
        "custom:\(id.uuidString)"
    }

    /// Returns the display name of a category.
    public static func label(for raw: String) -> String {
        if let id = ChallengeSections.customID(from: raw), let match = all().first(where: { $0.id == id }) {
            return match.name
        }
        if let builtIn = ChallengeCategory(rawValue: raw), ChallengeCategory.offered.contains(builtIn) {
            return builtIn.label
        }
        return ChallengeCategory.other.label
    }

    /// Maps a stored category to its picker value.
    public static func selectionKey(for raw: String) -> String {
        if raw == ChallengeCategory.sport.rawValue
            || raw == ChallengeCategory.abstinence.rawValue
            || raw == ChallengeCategory.other.rawValue {
            return raw
        }
        if let id = ChallengeSections.customID(from: raw), all().contains(where: { $0.id == id }) {
            return raw
        }
        return ChallengeCategory.other.rawValue
    }

    /// Returns all custom categories.
    public static func all() -> [CustomChallengeCategory] {
        if let cache { return cache }
        let decoded = LinkTable.decoded(.customCategories, as: [CustomChallengeCategory].self)["all"] ?? []
        cache = decoded
        return decoded
    }

    /// Adds a category with a non-empty name.
    @discardableResult
    public static func add(name: String, separate: Bool) -> CustomChallengeCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = CustomChallengeCategory(id: UUID(), name: trimmed, separate: separate)
        var items = all()
        items.append(created)
        save(items)
        return created
    }

    /// Updates a category.
    public static func update(id: UUID, name: String, separate: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = all()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        items[index].separate = separate
        save(items)
    }

    /// Removes a category.
    public static func remove(_ id: UUID) {
        var items = all()
        items.removeAll { $0.id == id }
        save(items)
    }

    /// Removes all categories.
    public static func reset() {
        cache = []
        LinkTable.clear(.customCategories)
        bump()
    }

    /// Exports the categories for a backup.
    public static func exportRecords() -> [BackupRecord] {
        all().map {
            BackupRecord(type: "customCategory", id: $0.id, strings: [$0.name], booleans: [$0.separate])
        }
    }

    /// Restores a category.
    public static func restore(_ record: BackupRecord) {
        let name = record.strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return }
        var items = all()
        let separate = record.booleans.first ?? false
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            items[index].name = name
            items[index].separate = separate
        } else {
            items.append(CustomChallengeCategory(id: record.id, name: name, separate: separate))
        }
        save(items)
    }

    /// Writes the categories.
    private static func save(_ items: [CustomChallengeCategory]) {
        cache = items
        LinkTable.replaceEncoded(.customCategories, with: items.isEmpty ? [:] : ["all": items])
        bump()
    }

    /// Signals that the categories changed.
    private static func bump() {
        let revision = AppDefaults.store.integer(forKey: revisionKey)
        AppDefaults.store.set(revision + 1, forKey: revisionKey)
    }
}
