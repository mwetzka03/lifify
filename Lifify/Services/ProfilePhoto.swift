import Foundation

/// The profile photo stays in the app. It is not written to the photo library.
enum ProfilePhotoStore {
    static let revisionKey = "lifify.profilePhotoRevision"

    static func load() -> Data? {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    static func save(_ data: Data) {
        let stored = MealPhotoFit.jpeg(data, maxEdge: 512) ?? data
        guard !stored.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try stored.write(to: file, options: .atomic)
            bump()
        } catch {
            return
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: file)
        bump()
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lifify", isDirectory: true)
            .appendingPathComponent("profile.jpg")
    }

    private static func bump() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }
}
