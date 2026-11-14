import Foundation

/// Optional challenge estimates and which challenges share a calendar slot.
/// Stored beside the data model so an existing store stays readable.
@MainActor
enum ChallengeTimeStore {
    private static let durationKey = "lifify.challengeDuration"
    private static let actualKey = "lifify.challengeActualMinutes"
    private static let memberKey = "lifify.challengeTimeMembers"
    private static let plannedKey = "lifify.challengeTimePlanned"
    private static var cachedDurations: [String: Int]?
    private static var cachedActuals: [String: Int]?
    private static var cachedMembers: [String: [String]]?
    private static var cachedPlanned: [String: Int]?

    static func minutes(for challengeID: UUID) -> Int? {
        let value = durations()[challengeID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    static func actualMinutes(for challengeID: UUID) -> Int? {
        let value = actuals()[challengeID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    static func setActualMinutes(_ minutes: Int?, for challengeID: UUID) {
        var map = actuals()
        if let minutes, minutes > 0 {
            map[challengeID.uuidString] = minutes
        } else {
            map.removeValue(forKey: challengeID.uuidString)
        }
        saveActuals(map)
    }

    static func setMinutes(_ minutes: Int?, for challengeID: UUID) {
        var map = durations()
        if let minutes, minutes > 0 {
            map[challengeID.uuidString] = minutes
        } else {
            map.removeValue(forKey: challengeID.uuidString)
        }
        saveDurations(map)
    }

    static func memberIDs(for eventID: UUID) -> [UUID] {
        (memberMap()[eventID.uuidString] ?? []).compactMap(UUID.init(uuidString:))
    }

    static func setMembers(_ ids: [UUID], for eventID: UUID) {
        var map = memberMap()
        let unique = ids.reduce(into: [UUID]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
        for key in Array(map.keys) where key != eventID.uuidString {
            let filtered = (map[key] ?? []).filter { raw in
                guard let id = UUID(uuidString: raw) else { return false }
                return !unique.contains(id)
            }
            map[key] = filtered
        }
        map[eventID.uuidString] = unique.map(\.uuidString)
        saveMembers(map)
    }

    static func plannedMinutes(for eventID: UUID) -> Int? {
        let value = plannedMap()[eventID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    static func setPlannedMinutes(_ minutes: Int?, for eventID: UUID) {
        var map = plannedMap()
        if let minutes, minutes > 0 {
            map[eventID.uuidString] = minutes
        } else {
            map.removeValue(forKey: eventID.uuidString)
        }
        savePlanned(map)
    }

    static func eventID(containing challengeID: UUID) -> UUID? {
        memberMap().first { _, values in
            values.contains(challengeID.uuidString)
        }.flatMap { UUID(uuidString: $0.key) }
    }

    static func eventIDs(containing challengeID: UUID) -> Set<UUID> {
        Set(memberMap().compactMap { key, values in
            guard values.contains(challengeID.uuidString) else { return nil }
            return UUID(uuidString: key)
        })
    }

    static func linkedEvents(for challengeID: UUID, in events: [ChallengeCalendarEvent]) -> [ChallengeCalendarEvent] {
        let members = eventIDs(containing: challengeID)
        return events.filter { event in
            !event.isReminderSuggestion && (event.linkedChallengeID == challengeID || members.contains(event.id))
        }
    }

    static func challengeIDs(on eventID: UUID, legacy: UUID?) -> [UUID] {
        var ids = memberIDs(for: eventID)
        if let legacy, !ids.contains(legacy) { ids.append(legacy) }
        return ids
    }

    static func removeChallenge(_ challengeID: UUID) {
        setMinutes(nil, for: challengeID)
        setActualMinutes(nil, for: challengeID)
        var map = memberMap()
        var changed = false
        for (key, values) in map {
            let filtered = values.filter { $0 != challengeID.uuidString }
            if filtered.count != values.count {
                map[key] = filtered
                changed = true
            }
        }
        if changed { saveMembers(map) }
    }

    static func removeEvent(_ eventID: UUID) {
        var members = memberMap()
        var planned = plannedMap()
        let removedMembers = members.removeValue(forKey: eventID.uuidString) != nil
        let removedPlanned = planned.removeValue(forKey: eventID.uuidString) != nil
        if removedMembers { saveMembers(members) }
        if removedPlanned { savePlanned(planned) }
    }

    static func reset() {
        cachedDurations = [:]
        cachedActuals = [:]
        cachedMembers = [:]
        cachedPlanned = [:]
        UserDefaults.standard.removeObject(forKey: durationKey)
        UserDefaults.standard.removeObject(forKey: actualKey)
        UserDefaults.standard.removeObject(forKey: memberKey)
        UserDefaults.standard.removeObject(forKey: plannedKey)
    }

    static func exportRecords() -> [BackupRecord] {
        var records: [BackupRecord] = []
        records += durations().compactMap { key, value in
            guard let id = UUID(uuidString: key), value > 0 else { return nil }
            return BackupRecord(type: "challengeDuration", id: id, integers: [value])
        }
        records += actuals().compactMap { key, value in
            guard let id = UUID(uuidString: key), value > 0 else { return nil }
            return BackupRecord(type: "challengeActual", id: id, integers: [value])
        }
        records += memberMap().compactMap { key, values in
            guard let id = UUID(uuidString: key) else { return nil }
            let uuids = values.compactMap(UUID.init(uuidString:))
            guard !uuids.isEmpty else { return nil }
            return BackupRecord(type: "challengeTimeMembers", id: id, uuids: uuids.map(Optional.init))
        }
        records += plannedMap().compactMap { key, value in
            guard let id = UUID(uuidString: key), value > 0 else { return nil }
            return BackupRecord(type: "challengeTimePlanned", id: id, integers: [value])
        }
        return records
    }

    static func restoreDuration(_ record: BackupRecord) {
        setMinutes(record.integers.first, for: record.id)
    }

    static func restoreActual(_ record: BackupRecord) {
        setActualMinutes(record.integers.first, for: record.id)
    }

    static func restoreMembers(_ record: BackupRecord) {
        let ids = record.uuids.compactMap { $0 }
        setMembers(ids, for: record.id)
    }

    static func restorePlanned(_ record: BackupRecord) {
        setPlannedMinutes(record.integers.first, for: record.id)
    }

    private static func durations() -> [String: Int] {
        if let cachedDurations { return cachedDurations }
        let decoded: [String: Int] = dictionary(durationKey) ?? [:]
        cachedDurations = decoded
        return decoded
    }

    private static func actuals() -> [String: Int] {
        if let cachedActuals { return cachedActuals }
        let decoded: [String: Int] = dictionary(actualKey) ?? [:]
        cachedActuals = decoded
        return decoded
    }

    private static func memberMap() -> [String: [String]] {
        if let cachedMembers { return cachedMembers }
        let decoded: [String: [String]] = dictionary(memberKey) ?? [:]
        cachedMembers = decoded
        return decoded
    }

    private static func plannedMap() -> [String: Int] {
        if let cachedPlanned { return cachedPlanned }
        let decoded: [String: Int] = dictionary(plannedKey) ?? [:]
        cachedPlanned = decoded
        return decoded
    }

    private static func dictionary<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveDurations(_ map: [String: Int]) {
        save(map, key: durationKey)
        cachedDurations = map
    }

    private static func saveActuals(_ map: [String: Int]) {
        save(map, key: actualKey)
        cachedActuals = map
    }

    private static func saveMembers(_ map: [String: [String]]) {
        save(map, key: memberKey)
        cachedMembers = map
    }

    private static func savePlanned(_ map: [String: Int]) {
        save(map, key: plannedKey)
        cachedPlanned = map
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
