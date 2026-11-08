import Foundation

/// Up to four challenges sit at the top of the challenges page.
enum ChallengePinStore {
    static let limit = 4
    static let revisionKey = "lifify.challengePinRevision"
    private static let key = "lifify.pinnedChallenges"

    static func ids() -> [UUID] {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return raw.compactMap(UUID.init(uuidString:))
    }

    static func contains(_ id: UUID) -> Bool {
        ids().contains(id)
    }

    static func pin(_ id: UUID) {
        let next = kept(ids(), adding: id)
        guard next != ids() else { return }
        save(next)
    }

    static func unpin(_ id: UUID) {
        let next = removed(ids(), id)
        guard next != ids() else { return }
        save(next)
    }

    static func toggle(_ id: UUID) {
        if contains(id) {
            unpin(id)
        } else {
            pin(id)
        }
    }

    static func kept(_ ids: [UUID], adding: UUID, limit: Int = ChallengePinStore.limit) -> [UUID] {
        if ids.contains(adding) { return ids }
        guard ids.count < limit else { return ids }
        return ids + [adding]
    }

    static func removed(_ ids: [UUID], _ id: UUID) -> [UUID] {
        ids.filter { $0 != id }
    }

    private static func save(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}

/// A sport challenge tied to a workout is finished only by starting and ending that workout.
enum ChallengeCheckoff {
    static func allowsHand(category: ChallengeCategory, linkedWorkouts: Int) -> Bool {
        category != .sport || linkedWorkouts == 0
    }
}
