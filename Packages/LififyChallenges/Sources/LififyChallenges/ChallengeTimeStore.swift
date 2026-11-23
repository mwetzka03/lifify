import Foundation
import LififyCore

/// Optional challenge estimates and which challenges share a calendar slot.
/// Stored beside the data model so an existing store stays readable.
@MainActor
public enum ChallengeTimeStore {
    private static var cachedDurations: [String: Int]?
    private static var cachedActuals: [String: Int]?
    private static var cachedMembers: [String: [String]]?
    private static var cachedPlanned: [String: Int]?

    /// Drops the in-memory copies.
    public static func clearCache() {
        cachedDurations = nil
        cachedActuals = nil
        cachedMembers = nil
        cachedPlanned = nil
    }

    /// Returns a challenge's planned minutes.
    public static func minutes(for challengeID: UUID) -> Int? {
        let value = durations()[challengeID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    /// Returns a challenge's actual minutes.
    public static func actualMinutes(for challengeID: UUID) -> Int? {
        let value = actuals()[challengeID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    /// Stores the actual minutes.
    public static func setActualMinutes(_ minutes: Int?, for challengeID: UUID) {
        var map = actuals()
        if let minutes, minutes > 0 {
            map[challengeID.uuidString] = minutes
        } else {
            map.removeValue(forKey: challengeID.uuidString)
        }
        saveActuals(map)
    }

    /// Stores the planned minutes.
    public static func setMinutes(_ minutes: Int?, for challengeID: UUID) {
        var map = durations()
        if let minutes, minutes > 0 {
            map[challengeID.uuidString] = minutes
        } else {
            map.removeValue(forKey: challengeID.uuidString)
        }
        saveDurations(map)
    }

    /// Lists the challenges on an event.
    public static func memberIDs(for eventID: UUID) -> [UUID] {
        (memberMap()[eventID.uuidString] ?? []).compactMap(UUID.init(uuidString:))
    }

    /// Sets an event's members. A challenge sits on one event only.
    public static func setMembers(_ ids: [UUID], for eventID: UUID) {
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

    /// Returns an event's planned minutes.
    public static func plannedMinutes(for eventID: UUID) -> Int? {
        let value = plannedMap()[eventID.uuidString] ?? 0
        return value > 0 ? value : nil
    }

    /// Stores an event's planned minutes.
    public static func setPlannedMinutes(_ minutes: Int?, for eventID: UUID) {
        var map = plannedMap()
        if let minutes, minutes > 0 {
            map[eventID.uuidString] = minutes
        } else {
            map.removeValue(forKey: eventID.uuidString)
        }
        savePlanned(map)
    }

    /// Finds the event holding a challenge.
    public static func eventID(containing challengeID: UUID) -> UUID? {
        memberMap().first { _, values in
            values.contains(challengeID.uuidString)
        }.flatMap { UUID(uuidString: $0.key) }
    }

    /// Lists the events holding a challenge.
    public static func eventIDs(containing challengeID: UUID) -> Set<UUID> {
        Set(memberMap().compactMap { key, values in
            guard values.contains(challengeID.uuidString) else { return nil }
            return UUID(uuidString: key)
        })
    }

    /// Lists the events linked to a challenge, directly or as a member.
    public static func linkedEvents(for challengeID: UUID, in events: [ChallengeCalendarEvent]) -> [ChallengeCalendarEvent] {
        let members = eventIDs(containing: challengeID)
        return events.filter { event in
            !event.isReminderSuggestion && (event.linkedChallengeID == challengeID || members.contains(event.id))
        }
    }

    /// Lists an event's challenges including its direct link.
    public static func challengeIDs(on eventID: UUID, legacy: UUID?) -> [UUID] {
        var ids = memberIDs(for: eventID)
        if let legacy, !ids.contains(legacy) { ids.append(legacy) }
        return ids
    }

    /// Removes everything stored for a challenge.
    public static func removeChallenge(_ challengeID: UUID) {
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

    /// Removes everything stored for an event.
    public static func removeEvent(_ eventID: UUID) {
        var members = memberMap()
        var planned = plannedMap()
        let removedMembers = members.removeValue(forKey: eventID.uuidString) != nil
        let removedPlanned = planned.removeValue(forKey: eventID.uuidString) != nil
        if removedMembers { saveMembers(members) }
        if removedPlanned { savePlanned(planned) }
    }

    /// Clears all time data.
    public static func reset() {
        cachedDurations = [:]
        cachedActuals = [:]
        cachedMembers = [:]
        cachedPlanned = [:]
        [.challengeDuration, .challengeActual, .challengeMembers, .challengePlanned].forEach(LinkTable.clear)
    }

    /// Exports the time data for a backup.
    public static func exportRecords() -> [BackupRecord] {
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

    /// Restores planned minutes.
    public static func restoreDuration(_ record: BackupRecord) {
        setMinutes(record.integers.first, for: record.id)
    }

    /// Restores actual minutes.
    public static func restoreActual(_ record: BackupRecord) {
        setActualMinutes(record.integers.first, for: record.id)
    }

    /// Restores event members.
    public static func restoreMembers(_ record: BackupRecord) {
        let ids = record.uuids.compactMap { $0 }
        setMembers(ids, for: record.id)
    }

    /// Restores an event's planned minutes.
    public static func restorePlanned(_ record: BackupRecord) {
        setPlannedMinutes(record.integers.first, for: record.id)
    }

    /// Reads the planned minutes.
    private static func durations() -> [String: Int] {
        if let cachedDurations { return cachedDurations }
        let decoded = LinkTable.decoded(.challengeDuration, as: Int.self)
        cachedDurations = decoded
        return decoded
    }

    /// Reads the actual minutes.
    private static func actuals() -> [String: Int] {
        if let cachedActuals { return cachedActuals }
        let decoded = LinkTable.decoded(.challengeActual, as: Int.self)
        cachedActuals = decoded
        return decoded
    }

    /// Reads the event members.
    private static func memberMap() -> [String: [String]] {
        if let cachedMembers { return cachedMembers }
        let decoded = LinkTable.decoded(.challengeMembers, as: [String].self)
        cachedMembers = decoded
        return decoded
    }

    /// Reads the events' planned minutes.
    private static func plannedMap() -> [String: Int] {
        if let cachedPlanned { return cachedPlanned }
        let decoded = LinkTable.decoded(.challengePlanned, as: Int.self)
        cachedPlanned = decoded
        return decoded
    }

    /// Writes the planned minutes.
    private static func saveDurations(_ map: [String: Int]) {
        LinkTable.replaceEncoded(.challengeDuration, with: map)
        cachedDurations = map
    }

    /// Writes the actual minutes.
    private static func saveActuals(_ map: [String: Int]) {
        LinkTable.replaceEncoded(.challengeActual, with: map)
        cachedActuals = map
    }

    /// Writes the event members.
    private static func saveMembers(_ map: [String: [String]]) {
        LinkTable.replaceEncoded(.challengeMembers, with: map)
        cachedMembers = map
    }

    /// Writes the events' planned minutes.
    private static func savePlanned(_ map: [String: Int]) {
        LinkTable.replaceEncoded(.challengePlanned, with: map)
        cachedPlanned = map
    }

}
