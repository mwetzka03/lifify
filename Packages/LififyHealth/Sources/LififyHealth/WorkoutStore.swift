import Foundation
import LififyChallenges
import LififyCore

/// Stores plans, sessions, and meals in one file.
@MainActor
public final class WorkoutStore: ObservableObject {
    public static let replacedNotification = Notification.Name("lifify.workouts.replaced")

    @Published public private(set) var plans: [WorkoutPlan] = []
    @Published public private(set) var sessions: [WorkoutSession] = []
    @Published public private(set) var meals: [MealEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    nonisolated(unsafe) private var replacementObserver: NSObjectProtocol?

    /// Loads the store from a file.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
        replacementObserver = NotificationCenter.default.addObserver(
            forName: Self.replacedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.load()
            }
        }
    }

    deinit {
        if let replacementObserver {
            NotificationCenter.default.removeObserver(replacementObserver)
        }
    }

    /// The default file location.
    public static func defaultFileURL() -> URL {
        AppFiles.supportDirectory
            .appendingPathComponent("Lifify", isDirectory: true)
            .appendingPathComponent("workouts.json")
    }

    /// Exports the whole store.
    public func exportSnapshotData() throws -> Data {
        try encoder.encode(Snapshot(plans: plans, sessions: sessions, meals: meals))
    }

    /// Replaces the stored file after validating it.
    public static func replaceStoredSnapshot(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(Snapshot.self, from: data)
        let url = defaultFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: replacedNotification, object: nil)
    }

    /// Deletes the stored file.
    public static func clearStored() {
        try? FileManager.default.removeItem(at: defaultFileURL())
        NotificationCenter.default.post(name: replacedNotification, object: nil)
    }

    /// Returns a plan.
    public func plan(id: UUID) -> WorkoutPlan? {
        plans.first { $0.id == id }
    }

    /// Returns a session.
    public func session(id: UUID) -> WorkoutSession? {
        sessions.first { $0.id == id }
    }

    /// Saves a plan.
    public func save(plan: WorkoutPlan) {
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

    /// Deletes a plan.
    public func deletePlan(id: UUID) {
        plans.removeAll { $0.id == id }
        persist()
    }

    /// Saves a session.
    public func save(session: WorkoutSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.finishedAt > $1.finishedAt }
        rememberFrequentWeights(from: session)
        persist()
    }

    /// Deletes a session.
    public func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    /// Saves a meal.
    public func save(meal: MealEntry) {
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.insert(meal, at: 0)
        }
        meals.sort { $0.date > $1.date }
        persist()
    }

    /// Deletes a meal.
    public func deleteMeal(id: UUID) {
        meals.removeAll { $0.id == id }
        persist()
    }

    /// Clears the store.
    public func reset() {
        plans = []
        sessions = []
        meals = []
        try? FileManager.default.removeItem(at: fileURL)
        persist()
    }

    /// Stores the weights a person uses most on the plan.
    private func rememberFrequentWeights(from session: WorkoutSession) {
        guard var plan = plans.first(where: { $0.id == session.planID }) else { return }
        let history = sessions
        for exerciseIndex in plan.exercises.indices {
            let code = plan.exercises[exerciseIndex].code
            for setIndex in plan.exercises[exerciseIndex].sets.indices {
                guard let frequent = WorkoutProgress.frequentWeight(
                    sessions: history,
                    exerciseCode: code,
                    setIndex: setIndex
                ) else { continue }
                plan.exercises[exerciseIndex].sets[setIndex].weightKg = frequent
            }
        }
        plan.updatedAt = .now
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        }
    }

    /// The file's content.
    private struct Snapshot: Codable {
        var plans: [WorkoutPlan]
        var sessions: [WorkoutSession]
        var meals: [MealEntry]

        /// The stored field names.
        private enum CodingKeys: String, CodingKey {
            case plans
            case sessions
            case meals
        }

        init(plans: [WorkoutPlan], sessions: [WorkoutSession], meals: [MealEntry]) {
            self.plans = plans
            self.sessions = sessions
            self.meals = meals
        }

        /// Decodes the file. Older files may lack meals.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plans = try container.decode([WorkoutPlan].self, forKey: .plans)
            sessions = try container.decode([WorkoutSession].self, forKey: .sessions)
            meals = try container.decodeIfPresent([MealEntry].self, forKey: .meals) ?? []
        }

        /// Encodes the file.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(plans, forKey: .plans)
            try container.encode(sessions, forKey: .sessions)
            try container.encode(meals, forKey: .meals)
        }
    }

    /// Reads the file.
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            plans = []
            sessions = []
            meals = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            plans = snapshot.plans.sorted { $0.updatedAt > $1.updatedAt }
            sessions = snapshot.sessions.sorted { $0.finishedAt > $1.finishedAt }
            meals = snapshot.meals.sorted { $0.date > $1.date }
        } catch {
            let broken = fileURL.deletingLastPathComponent().appendingPathComponent("workouts-broken.json")
            try? FileManager.default.removeItem(at: broken)
            try? FileManager.default.moveItem(at: fileURL, to: broken)
        }
    }

    /// Writes the file.
    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(Snapshot(plans: plans, sessions: sessions, meals: meals))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
