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

/// Groups stay in their own section until someone pins them.
enum ChallengeGroupPinStore {
    static let revisionKey = "lifify.challengeGroupPinRevision"
    private static let key = "lifify.pinnedChallengeGroups"

    static func ids() -> [UUID] {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        return raw.compactMap(UUID.init(uuidString:))
    }

    static func contains(_ id: UUID) -> Bool {
        ids().contains(id)
    }

    static func pin(_ id: UUID) {
        var next = ids()
        guard !next.contains(id) else { return }
        next.append(id)
        save(next)
    }

    static func unpin(_ id: UUID) {
        let next = ids().filter { $0 != id }
        guard next.count != ids().count else { return }
        save(next)
    }

    static func toggle(_ id: UUID) {
        if contains(id) {
            unpin(id)
        } else {
            pin(id)
        }
    }

    private static func save(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}

/// Where a group sits, and that a finished member still belongs to it.
enum ChallengeGroupBoard {
    static func showsInPinned(pinned: Bool) -> Bool { pinned }

    static func showsInOwnSection(pinned: Bool) -> Bool { !pinned }

    static func keepsFinishedMember(archived: Bool) -> Bool { !archived }
}

/// A sport challenge tied to a workout, and the nutrition challenge, finish on their own.
enum ChallengeCheckoff {
    static func allowsHand(
        category: ChallengeCategory,
        linkedWorkouts: Int,
        followsNutrition: Bool = false
    ) -> Bool {
        if followsNutrition { return false }
        return category != .sport || linkedWorkouts == 0
    }

    static func followsNutrition(_ identifier: String?) -> Bool {
        identifier == "nutrition:calories"
    }

    static func lockCaption(followsNutrition: Bool, linkedWorkouts: Int) -> String? {
        if followsNutrition {
            return L(
                "Zählt mit den Mahlzeiten dieses Tages.",
                "Counts from the meals of that day."
            )
        }
        if linkedWorkouts > 0 {
            return L(
                "Zählt, wenn das Training beendet ist.",
                "Counts when the workout is finished."
            )
        }
        return nil
    }
}
