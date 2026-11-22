import Foundation

/// A challenge can sit in the group it picked and in the group of its event.
public enum ChallengeGroups {
    public static func unique(_ ids: [UUID]) -> [UUID] {
        ids.reduce(into: [UUID]()) { result, id in
            if !result.contains(id) { result.append(id) }
        }
    }

    /// A stored list wins. An older record only has the single group.
    public static func ids(primary: UUID?, stored: String) -> [UUID] {
        let parsed = stored.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        if !parsed.isEmpty { return unique(parsed) }
        if let primary { return [primary] }
        return []
    }

    public static func stored(_ ids: [UUID]) -> String {
        unique(ids).map(\.uuidString).joined(separator: ",")
    }

    /// The chosen group and the event group both stay.
    public static func membership(chosen: UUID?, eventGroup: UUID?) -> [UUID] {
        unique([chosen, eventGroup].compactMap { $0 })
    }

    public static func contains(_ ids: [UUID], _ group: UUID) -> Bool {
        ids.contains(group)
    }
}
