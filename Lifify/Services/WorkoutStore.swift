import Foundation

@MainActor
final class WorkoutStore: ObservableObject {
    @Published private(set) var plans: [WorkoutPlan] = []
    @Published private(set) var sessions: [WorkoutSession] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lifify", isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("workouts.json")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func plan(id: UUID) -> WorkoutPlan? {
        plans.first { $0.id == id }
    }

    func session(id: UUID) -> WorkoutSession? {
        sessions.first { $0.id == id }
    }

    func save(plan: WorkoutPlan) {
        var stored = plan
        stored.updatedAt = .now
        if let index = plans.firstIndex(where: { $0.id == stored.id }) {
            plans[index] = stored
        } else {
            plans.insert(stored, at: 0)
        }
        plans.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func deletePlan(id: UUID) {
        plans.removeAll { $0.id == id }
        persist()
    }

    func save(session: WorkoutSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.finishedAt > $1.finishedAt }
        persist()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    private struct Snapshot: Codable {
        var plans: [WorkoutPlan]
        var sessions: [WorkoutSession]
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            plans = snapshot.plans.sorted { $0.updatedAt > $1.updatedAt }
            sessions = snapshot.sessions.sorted { $0.finishedAt > $1.finishedAt }
        } catch {
            let broken = fileURL.deletingLastPathComponent().appendingPathComponent("workouts-broken.json")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: fileURL, to: broken)
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(Snapshot(plans: plans, sessions: sessions))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
