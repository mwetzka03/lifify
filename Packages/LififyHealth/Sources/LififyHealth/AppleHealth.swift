import Foundation
import HealthKit
import LififyCore

/// One day's value from Apple Health.
public struct HealthDayValue: Identifiable, Equatable, Sendable {
    public let date: Date
    public let value: Double

    /// The day identifies the value.
    public var id: Date { date }

    /// Creates a value.
    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// The recent daily steps from Apple Health, newest first.
public struct HealthSummary: Equatable, Sendable {
    public var steps: [HealthDayValue] = []

    /// Creates a summary.
    public init(steps: [HealthDayValue] = []) {
        self.steps = steps
    }
}

/// Averages and chart days of the step count.
public struct StepStats: Equatable, Sendable {
    /// The steps so far today.
    public var today: Int
    /// The average of the last 7 complete days. `nil` without data.
    public var weekAverage: Int?
    /// The average of the last 30 complete days. `nil` without data.
    public var monthAverage: Int?
    /// The day with the most steps in the last 30 days.
    public var best: HealthDayValue?

    /// Reads the figures from the daily values.
    ///
    /// Averages leave out today, which is not over yet, and days without any data, which mean the
    /// phone was not carried rather than zero steps.
    ///
    /// - Parameters:
    ///   - days: The daily values in any order.
    ///   - now: The current time.
    ///   - calendar: The calendar of the days.
    /// - Returns: The figures.
    public static func make(_ days: [HealthDayValue], now: Date, calendar: Calendar = .current) -> StepStats {
        let today = calendar.startOfDay(for: now)
        let past = days.filter { calendar.startOfDay(for: $0.date) < today }
        return StepStats(
            today: Int(days.first { calendar.isDate($0.date, inSameDayAs: today) }?.value.rounded() ?? 0),
            weekAverage: average(past, within: 7, before: today, calendar: calendar),
            monthAverage: average(past, within: 30, before: today, calendar: calendar),
            best: days.filter { $0.date >= (calendar.date(byAdding: .day, value: -29, to: today) ?? today) }
                .max { $0.value < $1.value }
        )
    }

    /// The last days for a chart, oldest first. A day without data shows zero.
    ///
    /// - Parameters:
    ///   - days: The daily values in any order.
    ///   - count: The number of days including today.
    ///   - now: The current time.
    ///   - calendar: The calendar of the days.
    /// - Returns: One value per day.
    public static func chartDays(_ days: [HealthDayValue], count: Int, now: Date, calendar: Calendar = .current) -> [HealthDayValue] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let value = days.first { calendar.isDate($0.date, inSameDayAs: day) }?.value ?? 0
            return HealthDayValue(date: day, value: value)
        }
    }

    /// The rounded mean of the days in a window before today.
    private static func average(_ days: [HealthDayValue], within count: Int, before today: Date, calendar: Calendar) -> Int? {
        guard let start = calendar.date(byAdding: .day, value: -count, to: today) else { return nil }
        let window = days.filter { $0.date >= start }
        guard !window.isEmpty else { return nil }
        return Int((window.reduce(0) { $0 + $1.value } / Double(window.count)).rounded())
    }
}

/// Everything Lifify reads from and writes to Apple Health.
@MainActor
public protocol HealthDataSource: AnyObject {
    /// Says whether this device has Apple Health.
    var isAvailable: Bool { get }
    /// Shows the system's permission sheet.
    func requestAccess() async -> Bool
    /// Returns the newest body weight.
    func latestWeight() async -> (kilograms: Double, date: Date)?
    /// Returns the recent days, newest first.
    func summary(days: Int) async -> HealthSummary
    /// Saves a finished training as a workout.
    func saveWorkout(start: Date, end: Date) async -> Bool
}

/// The real connection to Apple Health.
@MainActor
public final class AppleHealthSource: HealthDataSource {
    private let store = HKHealthStore()

    /// Creates the source.
    public init() {}

    /// Says whether this device has Apple Health.
    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for weight and steps, and for writing workouts.
    public func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [HKQuantityType(.bodyMass), HKQuantityType(.stepCount)]
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
            return true
        } catch {
            return false
        }
    }

    /// Returns the newest body weight.
    public func latestWeight() async -> (kilograms: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.startDate)
    }

    /// Returns the recent days, newest first.
    public func summary(days: Int) async -> HealthSummary {
        HealthSummary(steps: await daily(.stepCount, unit: .count(), options: .cumulativeSum, days: days))
    }

    /// Saves a finished training as a strength workout.
    public func saveWorkout(start: Date, end: Date) async -> Bool {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout() != nil
        } catch {
            return false
        }
    }

    /// Reads one value per day.
    ///
    /// - Parameters:
    ///   - identifier: The kind of value.
    ///   - unit: The unit of the result.
    ///   - options: Sum or average.
    ///   - days: The number of days including today.
    /// - Returns: The days with data, newest first.
    private func daily(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        days: Int
    ) async -> [HealthDayValue] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: 1 - days, to: today) else { return [] }
        let range = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: range),
            options: options,
            anchorDate: today,
            intervalComponents: DateComponents(day: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var values: [HealthDayValue] = []
        collection.enumerateStatistics(from: start, to: .now) { statistics, _ in
            let quantity = options == .cumulativeSum ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity { values.append(HealthDayValue(date: statistics.startDate, value: quantity.doubleValue(for: unit))) }
        }
        return values.reversed()
    }
}

/// Keeps body data and workouts in step with Apple Health after the person allowed it.
@MainActor
public enum AppleHealthSync {
    public static let enabledKey = "lifify.appleHealth"
    public static let exportedKey = "lifify.appleHealthWorkouts"
    public static let weightDateKey = "lifify.appleHealthWeightDate"
    /// The days read for the step chart and the month average.
    public static let summaryDays = 31

    /// The connection. Tests replace it.
    public static var source: any HealthDataSource = AppleHealthSource()

    /// Whether the person turned the connection on. It is off by default.
    public static var isEnabled: Bool {
        AppDefaults.store.bool(forKey: enabledKey)
    }

    /// Turns the connection on after the system's permission sheet.
    ///
    /// - Returns: `true` when Apple Health can be used.
    public static func enable() async -> Bool {
        guard source.isAvailable, await source.requestAccess() else { return false }
        AppDefaults.store.set(true, forKey: enabledKey)
        await refreshWeight()
        return true
    }

    /// Takes over a newer weight into the body data, which keeps the calorie target current.
    public static func refreshWeight() async {
        guard isEnabled, let latest = await source.latestWeight(), latest.kilograms > 0 else { return }
        let known = AppDefaults.store.object(forKey: weightDateKey) as? Date ?? .distantPast
        guard latest.date > known else { return }
        AppDefaults.store.set(WorkoutFormat.rounded(latest.kilograms), forKey: UserBody.weightKey)
        AppDefaults.store.set(latest.date, forKey: weightDateKey)
    }

    /// Reads the values for the Health tab.
    public static func summary() async -> HealthSummary? {
        guard isEnabled else { return nil }
        return await source.summary(days: summaryDays)
    }

    /// Writes a finished training once.
    public static func export(_ session: WorkoutSession) async {
        guard isEnabled, session.finishedAt > session.startedAt else { return }
        var exported = AppDefaults.store.stringArray(forKey: exportedKey) ?? []
        let id = session.id.uuidString
        guard !exported.contains(id), await source.saveWorkout(start: session.startedAt, end: session.finishedAt) else { return }
        exported.append(id)
        AppDefaults.store.set(exported, forKey: exportedKey)
    }
}
