import Foundation
import LififyCore

@MainActor
public enum RewardPolicyStore {
    public static func allowsMultiplePurchases(for rewardID: UUID) -> Bool {
        LinkTable.map(.rewardPolicy)[rewardID.uuidString].map { $0 == "true" } ?? true
    }

    public static func setAllowsMultiplePurchases(_ allowed: Bool, for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: allowed ? "true" : "false")
    }

    public static func remove(for rewardID: UUID) {
        LinkTable.set(.rewardPolicy, key: rewardID.uuidString, value: nil)
    }
}
