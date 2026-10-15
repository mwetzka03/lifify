import Foundation

enum ExerciseMedia {
    static func isRemote(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("MANUAL-")
    }
}

struct WorkoutExerciseInfo: Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var detail: String
    var muscle: String
}

enum WorkoutAPIKey {
    static let storageKey = "workoutAPIKey"

    static var value: String {
        get {
            UserDefaults.standard.string(forKey: storageKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: storageKey
            )
        }
    }
}

enum WorkoutAPIError: LocalizedError {
    case missingKey
    case invalidURL
    case requestFailed(Int, String?)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            L("Hinterlege zuerst den Workout-API-Schlüssel.", "Add the Workout API key first.")
        case .invalidURL:
            L("Die Übungsadresse ist ungültig.", "The exercise address is invalid.")
        case .requestFailed(let status, let message):
            message ?? L("Die Workout API hat mit \(status) geantwortet.", "The Workout API responded with \(status).")
        }
    }
}

actor WorkoutAPIClient {
    static let shared = WorkoutAPIClient()

    private var allExercises: [WorkoutExerciseInfo]?

    func exercises(matching query: String) async throws -> [WorkoutExerciseInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if let allExercises { return allExercises }
            let loaded = try await fetchExercises(path: "/exercises", queryItems: [])
            allExercises = loaded
            return loaded
        }
        return try await fetchExercises(
            path: "/exercises/search",
            queryItems: [URLQueryItem(name: "q", value: trimmed)]
        )
    }

    func animationGIF(code: String) async throws -> Data {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await fetch(
            path: "/exercises/code/\(encoded)/animation",
            queryItems: [URLQueryItem(name: "variant", value: "basic")],
            accept: "image/gif"
        )
    }

    func imagePNG(code: String) async throws -> Data {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        return try await fetch(
            path: "/exercises/code/\(encoded)/image",
            queryItems: [
                URLQueryItem(name: "format", value: "png"),
                URLQueryItem(name: "variant", value: "basic"),
                URLQueryItem(name: "phase", value: "concentric")
            ],
            accept: "image/png"
        )
    }

    private func fetchExercises(path: String, queryItems: [URLQueryItem]) async throws -> [WorkoutExerciseInfo] {
        let data = try await fetch(path: path, queryItems: queryItems, accept: "application/json")
        let decoded = try JSONDecoder().decode([ExercisePayload].self, from: data)
        return decoded.map(\.info)
    }

    private func fetch(path: String, queryItems: [URLQueryItem], accept: String) async throws -> Data {
        let key = WorkoutAPIKey.value
        guard !key.isEmpty else { throw WorkoutAPIError.missingKey }
        guard var components = URLComponents(string: "https://api.workoutapi.com" + path) else {
            throw WorkoutAPIError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw WorkoutAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WorkoutAPIError.requestFailed(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
            throw WorkoutAPIError.requestFailed(http.statusCode, message)
        }
        return data
    }
}

private struct ErrorPayload: Decodable {
    var error: String?
}

private struct ExercisePayload: Decodable {
    var id: String
    var code: String
    var name: String
    var description: String?
    var primaryMuscles: [MusclePayload]?

    var info: WorkoutExerciseInfo {
        WorkoutExerciseInfo(
            id: id,
            code: code,
            name: name,
            detail: description ?? "",
            muscle: primaryMuscles?.map(\.name).joined(separator: ", ") ?? ""
        )
    }
}

private struct MusclePayload: Decodable {
    var name: String
}
