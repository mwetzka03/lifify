import Foundation

enum ExerciseImageStore {
    static func data(for code: String) -> Data? {
        guard let url = fileURL(for: code) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func save(_ data: Data, code: String) {
        guard let url = fileURL(for: code) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL(for code: String) -> URL? {
        let safe = code.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !safe.isEmpty else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lifify", isDirectory: true)
            .appendingPathComponent("ExerciseImages", isDirectory: true)
        return support.appendingPathComponent("\(safe).png")
    }
}

@MainActor
enum ExerciseImageLoader {
    private static var inflight: [String: Task<Data?, Never>] = [:]

    static func load(code: String) async -> Data? {
        if let cached = ExerciseImageStore.data(for: code) { return cached }
        if let task = inflight[code] { return await task.value }
        let task = Task<Data?, Never> {
            guard let data = try? await WorkoutAPIClient.shared.imagePNG(code: code), !data.isEmpty else {
                return nil
            }
            ExerciseImageStore.save(data, code: code)
            return data
        }
        inflight[code] = task
        let data = await task.value
        inflight[code] = nil
        return data
    }
}
