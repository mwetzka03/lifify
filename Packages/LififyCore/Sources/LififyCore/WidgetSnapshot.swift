import ActivityKit
import Foundation

/// A challenge as a widget shows it.
public struct WidgetChallenge: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// `false` for sport with a linked training, which finishes only through that training.
    public var canCheckOff: Bool
    /// The training a tap opens instead of a check-off.
    public var planID: UUID?

    /// Creates a widget challenge.
    public init(id: UUID, title: String, canCheckOff: Bool, planID: UUID? = nil) {
        self.id = id
        self.title = title
        self.canCheckOff = canCheckOff
        self.planID = planID
    }
}

/// The amounts of the finance widgets. They are absent while the lock hides them.
public struct WidgetFinance: Codable, Equatable, Sendable {
    public var remainingCents: Int
    public var plannedCents: Int
    public var dailyCents: Int?
    public var depotCents: Int
    public var depotChangeCents: Int?

    /// Creates the amounts.
    public init(remainingCents: Int, plannedCents: Int, dailyCents: Int?, depotCents: Int, depotChangeCents: Int?) {
        self.remainingCents = remainingCents
        self.plannedCents = plannedCents
        self.dailyCents = dailyCents
        self.depotCents = depotCents
        self.depotChangeCents = depotChangeCents
    }

    /// The used share of the budget, from 0 to 1.
    public var usedFraction: Double {
        guard plannedCents > 0 else { return remainingCents < 0 ? 1 : 0 }
        return min(max(Double(plannedCents - remainingCents) / Double(plannedCents), 0), 1)
    }
}

/// A calendar slot or training with its time.
public struct WidgetAppointment: Codable, Equatable, Sendable {
    public var title: String
    public var date: Date
    public var planID: UUID?

    /// Creates an appointment.
    public init(title: String, date: Date, planID: UUID? = nil) {
        self.title = title
        self.date = date
        self.planID = planID
    }
}

/// Everything the widgets show. The app writes it after each change.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var isGerman: Bool
    public var paletteRaw: String
    /// `nil` while the Finance lock hides amounts from widgets.
    public var finance: WidgetFinance?
    public var hasFinanceLock: Bool
    /// The open challenges by `yyyy-MM-dd`, for today and tomorrow.
    public var challengesByDay: [String: [WidgetChallenge]]
    public var nextSlot: WidgetAppointment?
    public var nextTraining: WidgetAppointment?
    public var coins: Int
    public var longestStreak: Int
    /// Today's steps and when Apple Health was last read, or `nil` while it is off.
    public var steps: WidgetSteps?

    /// Creates a snapshot.
    public init(
        generatedAt: Date,
        isGerman: Bool,
        paletteRaw: String,
        finance: WidgetFinance?,
        hasFinanceLock: Bool,
        challengesByDay: [String: [WidgetChallenge]],
        nextSlot: WidgetAppointment?,
        nextTraining: WidgetAppointment?,
        coins: Int,
        longestStreak: Int,
        steps: WidgetSteps? = nil
    ) {
        self.generatedAt = generatedAt
        self.isGerman = isGerman
        self.paletteRaw = paletteRaw
        self.finance = finance
        self.hasFinanceLock = hasFinanceLock
        self.challengesByDay = challengesByDay
        self.nextSlot = nextSlot
        self.nextTraining = nextTraining
        self.coins = coins
        self.longestStreak = longestStreak
        self.steps = steps
    }

    /// A negative wallet locks the shop.
    public var isShopLocked: Bool { coins < 0 }

    /// The open challenges of a day.
    public func challenges(on date: Date) -> [WidgetChallenge] {
        challengesByDay[date.dayKey] ?? []
    }
}

/// The step count a widget shows, with the time it was read.
public struct WidgetSteps: Codable, Equatable, Sendable {
    public var count: Int
    public var readAt: Date

    /// Creates a step count.
    public init(count: Int, readAt: Date) {
        self.count = count
        self.readAt = readAt
    }
}

/// A check-off made in a widget, waiting for the app to book it.
public struct WidgetCheckOff: Codable, Equatable, Sendable {
    public var challengeID: UUID
    public var date: Date

    /// Creates a waiting check-off.
    public init(challengeID: UUID, date: Date) {
        self.challengeID = challengeID
        self.date = date
    }
}

/// The files shared between the app and its widgets.
///
/// The database stays in the app. Only the app writes bookings, so a widget can never
/// damage it: a widget's check-off waits here until the app books it with all its rules.
public enum WidgetStore {
    public static let groupID = "group.com.mwetzka03.lifify"
    /// The file with the data the widgets show.
    public static let snapshotFile = "widget-snapshot.json"
    /// The file with check-offs waiting for the app.
    public static let queueFile = "widget-checkoffs.json"

    /// The shared folder, or `nil` while the App Group is not set up.
    public static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    /// Writes the snapshot.
    public static func write(_ snapshot: WidgetSnapshot, in folder: URL? = directory) {
        guard let folder, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: folder.appendingPathComponent(snapshotFile), options: .atomic)
    }

    /// Reads the snapshot.
    public static func read(in folder: URL? = directory) -> WidgetSnapshot? {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(snapshotFile)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Queues a check-off and removes the challenge from the shown list at once.
    public static func enqueue(_ checkOff: WidgetCheckOff, in folder: URL? = directory) {
        guard let folder else { return }
        var queue = pending(in: folder)
        guard !queue.contains(where: { $0.challengeID == checkOff.challengeID && $0.date.dayKey == checkOff.date.dayKey }) else { return }
        queue.append(checkOff)
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: folder.appendingPathComponent(queueFile), options: .atomic)
        }
        if var snapshot = read(in: folder) {
            let key = checkOff.date.dayKey
            snapshot.challengesByDay[key]?.removeAll { $0.id == checkOff.challengeID }
            write(snapshot, in: folder)
        }
    }

    /// Returns the waiting check-offs.
    public static func pending(in folder: URL? = directory) -> [WidgetCheckOff] {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(queueFile)) else { return [] }
        return (try? JSONDecoder().decode([WidgetCheckOff].self, from: data)) ?? []
    }

    /// Removes booked check-offs and keeps any that arrived in the meantime.
    public static func clear(_ booked: [WidgetCheckOff], in folder: URL? = directory) {
        guard let folder else { return }
        let remaining = pending(in: folder).filter { !booked.contains($0) }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(queueFile))
        } else if let data = try? JSONEncoder().encode(remaining) {
            try? data.write(to: folder.appendingPathComponent(queueFile), options: .atomic)
        }
    }
}

/// The link a widget opens to start a training.
public enum WidgetRoute {
    private static let prefix = "training:"

    /// The link of a plan.
    public static func url(plan: UUID) -> URL? {
        URL(string: "lifify://training?plan=\(plan.uuidString)")
    }

    /// The in-app route of a training link, or `nil` for any other link.
    public static func route(from url: URL) -> String? {
        guard url.scheme == "lifify", url.host == "training",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "plan" })?.value,
              let plan = UUID(uuidString: value) else { return nil }
        return prefix + plan.uuidString
    }

    /// The plan of an in-app route.
    public static func plan(in route: String?) -> UUID? {
        guard let route, route.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(route.dropFirst(prefix.count)))
    }
}

/// The Live Activity of a running training.
public struct WorkoutActivityAttributes: ActivityAttributes {
    /// The values that change during the session.
    public struct ContentState: Codable, Hashable, Sendable {
        public var exercise: String
        public var setNumber: Int
        public var setCount: Int
        public var restEndsAt: Date?

        /// Creates a state.
        public init(exercise: String, setNumber: Int, setCount: Int, restEndsAt: Date?) {
            self.exercise = exercise
            self.setNumber = setNumber
            self.setCount = setCount
            self.restEndsAt = restEndsAt
        }
    }

    public var planName: String
    public var startedAt: Date

    /// Creates the attributes.
    public init(planName: String, startedAt: Date) {
        self.planName = planName
        self.startedAt = startedAt
    }
}

/// Finds what a running session shows in its Live Activity.
public enum WorkoutActivityProgress {
    /// The first exercise with an open set, or the last one when all sets are done.
    ///
    /// - Parameters:
    ///   - session: The running session.
    ///   - restEndsAt: The end of the running rest.
    /// - Returns: The state for the Live Activity.
    public static func state(of session: WorkoutSession, restEndsAt: Date?) -> WorkoutActivityAttributes.ContentState {
        let exercise = session.exercises.first { $0.sets.contains { !$0.completed } } ?? session.exercises.last
        let sets = exercise?.sets ?? []
        let done = sets.filter(\.completed).count
        return WorkoutActivityAttributes.ContentState(
            exercise: exercise?.name ?? session.planName,
            setNumber: min(done + 1, max(sets.count, 1)),
            setCount: sets.count,
            restEndsAt: restEndsAt
        )
    }
}
