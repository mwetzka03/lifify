import Foundation
import LififyCore

/// Remembers dismissed challenge suggestions, so a reminder that was turned down does not come back.
@MainActor
public enum RecommendationRejection {
    /// The key of a suggestion: its reminder identifier, or its own identifier without one.
    public static func key(of event: ChallengeCalendarEvent) -> String {
        event.externalIdentifier ?? event.id.uuidString
    }

    /// Says whether a suggestion was dismissed.
    public static func isRejected(_ event: ChallengeCalendarEvent) -> Bool {
        LinkTable.map(.recommendationRejection)[key(of: event)] != nil
    }

    /// Dismisses a suggestion for good.
    public static func reject(_ event: ChallengeCalendarEvent) {
        LinkTable.set(.recommendationRejection, key: key(of: event), value: "1")
    }
}
