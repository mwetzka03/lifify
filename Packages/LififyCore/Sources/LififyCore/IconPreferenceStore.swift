import Foundation

/// The symbol a person picked for an entry.
@MainActor
public enum IconPreferenceStore {
    /// Returns the picked symbol, or the fallback.
    public static func icon(for id: UUID, fallback: String) -> String {
        storedIcon(for: id) ?? fallback
    }

    /// Returns the picked symbol, if any.
    public static func storedIcon(for id: UUID) -> String? {
        LinkTable.map(.icon)[id.uuidString]
    }

    /// Stores the picked symbol.
    public static func set(_ icon: String, for id: UUID) {
        LinkTable.set(.icon, key: id.uuidString, value: icon)
    }

    /// Removes the picked symbol.
    public static func remove(for id: UUID) {
        LinkTable.set(.icon, key: id.uuidString, value: nil)
    }
}
