import Foundation
import LififyCore

/// Up to four challenges sit at the top of the challenges page.
@MainActor
public enum ChallengePinStore {
    public static let limit = 4
    public static let revisionKey = "lifify.challengePinRevision"

    public static func ids() -> [UUID] {
        (LinkTable.map(.pinnedChallenges)["all"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    public static func contains(_ id: UUID) -> Bool {
        ids().contains(id)
    }

    public static func pin(_ id: UUID) {
        let next = kept(ids(), adding: id)
        guard next != ids() else { return }
        save(next)
    }

    public static func unpin(_ id: UUID) {
        let next = removed(ids(), id)
        guard next != ids() else { return }
        save(next)
    }

    public static func toggle(_ id: UUID) {
        if contains(id) {
            unpin(id)
        } else {
            pin(id)
        }
    }

    public static func kept(_ ids: [UUID], adding: UUID, limit: Int = ChallengePinStore.limit) -> [UUID] {
        if ids.contains(adding) { return ids }
        guard ids.count < limit else { return ids }
        return ids + [adding]
    }

    public static func removed(_ ids: [UUID], _ id: UUID) -> [UUID] {
        ids.filter { $0 != id }
    }

    private static func save(_ ids: [UUID]) {
        LinkTable.replace(.pinnedChallenges, with: ids.isEmpty ? [:] : ["all": ids.map(\.uuidString).joined(separator: ",")])
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}

/// Pinned challenges sit above the filter. The lists under the filter leave them out.
public enum ChallengePinLayout {
    public static func below(ids: [UUID], pinned: [UUID]) -> [UUID] {
        let held = Set(pinned)
        return ids.filter { !held.contains($0) }
    }
}

/// Groups stay in their own section until someone pins them.
@MainActor
public enum ChallengeGroupPinStore {
    public static let revisionKey = "lifify.challengeGroupPinRevision"

    public static func ids() -> [UUID] {
        (LinkTable.map(.pinnedGroups)["all"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    public static func contains(_ id: UUID) -> Bool {
        ids().contains(id)
    }

    public static func pin(_ id: UUID) {
        var next = ids()
        guard !next.contains(id) else { return }
        next.append(id)
        save(next)
    }

    public static func unpin(_ id: UUID) {
        let next = ids().filter { $0 != id }
        guard next.count != ids().count else { return }
        save(next)
    }

    public static func toggle(_ id: UUID) {
        if contains(id) {
            unpin(id)
        } else {
            pin(id)
        }
    }

    private static func save(_ ids: [UUID]) {
        LinkTable.replace(.pinnedGroups, with: ids.isEmpty ? [:] : ["all": ids.map(\.uuidString).joined(separator: ",")])
        AppDefaults.store.set(AppDefaults.store.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}

/// Where a group sits, and that a finished member still belongs to it.
public enum ChallengeGroupBoard {
    public static func showsInPinned(pinned: Bool) -> Bool { pinned }

    public static func showsInOwnSection(pinned: Bool) -> Bool { !pinned }

    public static func keepsFinishedMember(archived: Bool) -> Bool { !archived }
}

/// A sport challenge tied to a workout, and the nutrition challenge, finish on their own.
public enum ChallengeCheckoff {
    public static func allowsHand(
        category: ChallengeCategory,
        linkedWorkouts: Int,
        followsNutrition: Bool = false
    ) -> Bool {
        if followsNutrition { return false }
        return category != .sport || linkedWorkouts == 0
    }

    public static func followsNutrition(_ identifier: String?) -> Bool {
        identifier == "nutrition:calories"
    }

    public static func lockCaption(followsNutrition: Bool, linkedWorkouts: Int) -> String? {
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
