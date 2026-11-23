import Foundation
import LififyCore

/// Whether a reward can be bought more than once.
@MainActor
public enum RewardPolicyStore {
    /// Returns the stored choice.
    public static func allowsMultiplePurchases(for rewardID: UUID) -> Bool {
        LinkTable.map(.rewardPolicy)[rewardID.uuidString].map { $0 == "true" } ?? true
    }

    /// Stores the choice.
    public static func setAllowsMultiplePurchases(_ allowed: Bool, for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: allowed ? "true" : "false")
    }

    /// Removes the choice.
    public static func remove(for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: nil)
    }
}
