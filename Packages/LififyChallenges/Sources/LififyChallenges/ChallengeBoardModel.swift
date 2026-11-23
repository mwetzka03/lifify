import Foundation
import LififyCore
import Observation

/// All completions grouped by challenge, so a card never scans the whole history.
public struct ChallengeCompletionIndex {
    private let byChallenge: [UUID: [ChallengeCompletion]]

    /// Groups the completions by their challenge.
    public init(_ completions: [ChallengeCompletion]) {
        byChallenge = Dictionary(grouping: completions, by: \.challengeID)
    }

    /// The completions of one challenge.
    public func completions(for challengeID: UUID) -> [ChallengeCompletion] {
        byChallenge[challengeID] ?? []
    }

    /// Whether the challenge was ever completed.
    public func hasCompletion(_ challengeID: UUID) -> Bool {
        byChallenge[challengeID] != nil
    }
}

/// Holds the completion index of the challenge board between renders.
///
/// The index is deliberately not observed: reading it during `body` must not cause a render.
@MainActor
@Observable
public final class ChallengeBoardModel {
    /// The inputs of the index.
    private struct Key: Equatable {
        let generation: Int
        let count: Int
    }

    @ObservationIgnored private var key: Key?
    @ObservationIgnored private var stored = ChallengeCompletionIndex([])

    /// Creates an empty model.
    public init() {}

    /// Returns the index, rebuilding it after a saved change.
    ///
    /// - Parameters:
    ///   - completions: All completions.
    ///   - hasUnsavedChanges: Whether unsaved edits exist, which skip the stored index.
    /// - Returns: The completions grouped by challenge.
    public func index(completions: [ChallengeCompletion], hasUnsavedChanges: Bool) -> ChallengeCompletionIndex {
        let current = Key(generation: ModelChangeCounter.value, count: completions.count)
        if !hasUnsavedChanges, key == current { return stored }
        let index = ChallengeCompletionIndex(completions)
        key = hasUnsavedChanges ? nil : current
        stored = index
        return index
    }
}
