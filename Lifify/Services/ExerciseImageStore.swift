import Foundation

enum ExerciseImageStore {
    static func data(for code: String) -> Data? {
        guard let url = fileURL(for: code) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func save(_ data: Data, code: String) {
        guard let url = fileURL(for: code) else { return }
        write(data, to: url)
    }

    static func animationData(for code: String) -> Data? {
        guard let url = animationURL(for: code) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func saveAnimation(_ data: Data, code: String) {
        guard let url = animationURL(for: code) else { return }
        write(data, to: url)
    }

    static func removeAll() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lifify", isDirectory: true)
            .appendingPathComponent("ExerciseImages", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func write(_ data: Data, to url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL(for code: String) -> URL? {
        guard let safe = safeCode(code) else { return nil }
        return imageDirectory.appendingPathComponent("\(safe).png")
    }

    private static func animationURL(for code: String) -> URL? {
        guard let safe = safeCode(code) else { return nil }
        return imageDirectory.appendingPathComponent("\(safe).gif")
    }

    private static var imageDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lifify", isDirectory: true)
            .appendingPathComponent("ExerciseImages", isDirectory: true)
    }

    private static func safeCode(_ code: String) -> String? {
        let safe = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        return safe.isEmpty ? nil : safe
    }
}

@MainActor
enum ExerciseImageLoader {
    private static var inflight: [String: Task<Data?, Never>] = [:]

    static func load(code: String) async -> Data? {
        if let cached = ExerciseImageStore.animationData(for: code), !cached.isEmpty { return cached }
        guard ExerciseMedia.isRemote(code) else { return nil }
        if let task = inflight[code] { return await task.value }
        let task = Task<Data?, Never> {
            guard let data = try? await gif(for: code), !data.isEmpty else { return nil }
            return data
        }
        inflight[code] = task
        let data = await task.value
        inflight[code] = nil
        return data
    }

    static func gif(for code: String) async throws -> Data {
        if let cached = ExerciseImageStore.animationData(for: code), !cached.isEmpty { return cached }
        guard let url = ExerciseCatalog.gifURL(for: code) else { return Data() }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            return Data()
        }
        ExerciseImageStore.saveAnimation(data, code: code)
        return data
    }
}
