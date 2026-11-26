import Foundation
import LififyCore
import SwiftData

/// Keeps the person's own changes when a statement is imported again and its bookings are rebuilt.
///
/// A repeated Trade Republic import deletes the bookings of the earlier statement and books them anew.
/// Without this, refund links, fixed-cost and budget assignments, splits, and picked icons of those
/// bookings would be lost, because they point to the old booking IDs.
@MainActor
public enum ImportCarryOver {
    /// The assignments of one rebuilt booking, found again through its import fingerprint.
    public struct Kept: Sendable {
        public let oldID: UUID
        public let fixedCostID: UUID?
        public let variableBudgetID: UUID?
        public let shoppingItemID: UUID?
    }

    /// Remembers the assignments of bookings that are about to be rebuilt.
    public static func capture(_ doomed: [LedgerEntry]) -> [String: Kept] {
        var kept: [String: Kept] = [:]
        for entry in doomed {
            guard let fingerprint = entry.importFingerprint else { continue }
            kept[fingerprint] = Kept(
                oldID: entry.id,
                fixedCostID: entry.fixedCostID,
                variableBudgetID: entry.variableBudgetID,
                shoppingItemID: entry.shoppingItemID
            )
        }
        return kept
    }

    /// Moves the remembered changes onto the rebuilt bookings.
    ///
    /// - Parameters:
    ///   - kept: What `capture` remembered, by fingerprint.
    ///   - entries: The bookings after the import.
    ///   - context: The database context, for the splits.
    /// - Returns: The old IDs that found no rebuilt booking; their splits are removed.
    @discardableResult
    public static func restore(_ kept: [String: Kept], into entries: [LedgerEntry], context: ModelContext) -> Set<UUID> {
        guard !kept.isEmpty else { return [] }
        var renamed: [String: String] = [:]
        for entry in entries {
            guard let fingerprint = entry.importFingerprint, let old = kept[fingerprint], old.oldID != entry.id else { continue }
            if entry.fixedCostID == nil { entry.fixedCostID = old.fixedCostID }
            if entry.variableBudgetID == nil { entry.variableBudgetID = old.variableBudgetID }
            if entry.shoppingItemID == nil { entry.shoppingItemID = old.shoppingItemID }
            renamed[old.oldID.uuidString] = entry.id.uuidString
        }
        renameLinks(renamed)
        let lost = Set(kept.values.map(\.oldID)).subtracting(renamed.keys.compactMap(UUID.init(uuidString:)))
        moveSplits(renamed: renamed, lost: lost, context: context)
        return lost
    }

    /// Replaces old booking IDs in every stored link, keys and values alike.
    static func renameLinks(_ renamed: [String: String]) {
        guard !renamed.isEmpty else { return }
        for kind in LinkKind.allCases {
            let map = LinkTable.map(kind)
            guard !map.isEmpty else { continue }
            var changed = false
            var result: [String: String] = [:]
            for (key, value) in map {
                let newKey = rename(key, renamed)
                let newValue = rename(value, renamed)
                changed = changed || newKey != key || newValue != value
                result[newKey] = newValue
            }
            if changed { LinkTable.replace(kind, with: result) }
        }
    }

    /// Replaces each old ID inside a stored text, which may be a plain ID or a combined key.
    private static func rename(_ text: String, _ renamed: [String: String]) -> String {
        if let direct = renamed[text] { return direct }
        guard text.count > 36 else { return text }
        var result = text
        for (old, new) in renamed where result.contains(old) {
            result = result.replacingOccurrences(of: old, with: new)
        }
        return result
    }

    /// Points the splits of rebuilt bookings to the new IDs and drops those of vanished bookings.
    private static func moveSplits(renamed: [String: String], lost: Set<UUID>, context: ModelContext) {
        let splits = (try? context.fetch(FetchDescriptor<TransactionSplit>())) ?? []
        for split in splits {
            if let new = renamed[split.transactionID.uuidString].flatMap(UUID.init(uuidString:)) {
                split.transactionID = new
            } else if lost.contains(split.transactionID) {
                context.delete(split)
            }
        }
    }
}
