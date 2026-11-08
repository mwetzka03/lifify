import Foundation

struct CustomChallengeCategory: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var separate: Bool
}

/// How the active challenge list is split into headings.
/// Sport and abstinence always stand alone. A custom category does too when it is marked separate.
/// Everything else shares one section.
enum ChallengeSections {
    struct Challenge: Equatable {
        var id: UUID
        var categoryRaw: String
    }

    struct Custom: Equatable {
        var id: UUID
        var name: String
        var separate: Bool
    }

    struct Section: Equatable, Identifiable {
        var id: String
        var showsTitle: Bool
        var challengeIDs: [UUID]
    }

    static func customID(from raw: String) -> UUID? {
        let prefix = "custom:"
        guard raw.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(prefix.count)))
    }

    static func make(challenges: [Challenge], customs: [Custom]) -> [Section] {
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
enum ChallengeCategoryStore {
    static let revisionKey = "lifify.customCategoryRevision"
    private static let storageKey = "lifify.customCategories"
    private static var cache: [CustomChallengeCategory]?

    static func raw(_ id: UUID) -> String {
        "custom:\(id.uuidString)"
    }

    static func label(for raw: String) -> String {
        if let id = ChallengeSections.customID(from: raw), let match = all().first(where: { $0.id == id }) {
            return match.name
        }
        if let builtIn = ChallengeCategory(rawValue: raw), ChallengeCategory.offered.contains(builtIn) {
            return builtIn.label
        }
        return ChallengeCategory.other.label
    }

    static func selectionKey(for raw: String) -> String {
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

    static func all() -> [CustomChallengeCategory] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomChallengeCategory].self, from: data)
        else {
            cache = []
            return []
        }
        cache = decoded
        return decoded
    }

    @discardableResult
    static func add(name: String, separate: Bool) -> CustomChallengeCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = CustomChallengeCategory(id: UUID(), name: trimmed, separate: separate)
        var items = all()
        items.append(created)
        save(items)
        return created
    }

    static func update(id: UUID, name: String, separate: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = all()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        items[index].separate = separate
        save(items)
    }

    static func remove(_ id: UUID) {
        var items = all()
        items.removeAll { $0.id == id }
        save(items)
    }

    static func reset() {
        cache = []
        UserDefaults.standard.removeObject(forKey: storageKey)
        bump()
    }

    static func exportRecords() -> [BackupRecord] {
        all().map {
            BackupRecord(type: "customCategory", id: $0.id, strings: [$0.name], booleans: [$0.separate])
        }
    }

    static func restore(_ record: BackupRecord) {
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

    private static func save(_ items: [CustomChallengeCategory]) {
        cache = items
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        bump()
    }

    private static func bump() {
        let revision = UserDefaults.standard.integer(forKey: revisionKey)
        UserDefaults.standard.set(revision + 1, forKey: revisionKey)
    }
}
