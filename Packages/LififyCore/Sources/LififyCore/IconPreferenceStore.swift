import Foundation

@MainActor
public enum IconPreferenceStore {
    public static func icon(for id: UUID, fallback: String) -> String {
        storedIcon(for: id) ?? fallback
    }

    public static func storedIcon(for id: UUID) -> String? {
        LinkTable.map(.icon)[id.uuidString]
    }

    public static func set(_ icon: String, for id: UUID) {
        LinkTable.set(.icon, key: id.uuidString, value: icon)
    }

    public static func remove(for id: UUID) {
        LinkTable.set(.icon, key: id.uuidString, value: nil)
    }
}
