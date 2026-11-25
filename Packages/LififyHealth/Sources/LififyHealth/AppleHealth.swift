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

    /// The days of one chart page, oldest first. A day without data shows zero.
    ///
    /// Page 0 ends today, page 1 ends the day before page 0 starts, and so on.
    ///
    /// - Parameters:
    ///   - days: The daily values in any order.
    ///   - count: The number of days on a page.
    ///   - page: How many pages back from today.
    ///   - now: The current time.
    ///   - calendar: The calendar of the days.
    /// - Returns: One value per day.
    public static func chartDays(
        _ days: [HealthDayValue],
        count: Int,
        page: Int = 0,
        now: Date,
        calendar: Calendar = .current
    ) -> [HealthDayValue] {
        let today = calendar.startOfDay(for: now)
        let end = count * max(page, 0)
        return (end..<(end + count)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let value = days.first { calendar.isDate($0.date, inSameDayAs: day) }?.value ?? 0
            return HealthDayValue(date: day, value: value)
        }
    }

    /// The 24 hours of a day for the hour chart, with zero for hours without steps.
    ///
    /// - Parameters:
    ///   - hours: The hourly values Apple Health returned.
    ///   - day: Any moment of the shown day.
    ///   - calendar: The calendar of the day.
    /// - Returns: One value per hour, from midnight on; a short or long day on a clock change keeps its real hours.
    public static func hourly(_ hours: [HealthDayValue], on day: Date, calendar: Calendar = .current) -> [HealthDayValue] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var slots: [HealthDayValue] = []
        var hour = start
        while hour < end {
            let value = hours.first { calendar.isDate($0.date, equalTo: hour, toGranularity: .hour) }?.value ?? 0
            slots.append(HealthDayValue(date: hour, value: value))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = next
        }
        return slots
    }

    /// The average of a chart page, leaving out today and days without data.
    ///
    /// - Parameters:
    ///   - page: The days of the page.
    ///   - now: The current time.
    ///   - calendar: The calendar of the days.
    /// - Returns: The rounded mean, or `nil` when no finished day has data.
    public static func average(of page: [HealthDayValue], now: Date, calendar: Calendar = .current) -> Int? {
        let today = calendar.startOfDay(for: now)
        let counted = page.filter { $0.value > 0 && calendar.startOfDay(for: $0.date) < today }
        guard !counted.isEmpty else { return nil }
        return Int((counted.reduce(0) { $0 + $1.value } / Double(counted.count)).rounded())
    }

    /// The total and the daily average of a date range.
    ///
    /// - Parameters:
    ///   - days: The daily values in any order.
    ///   - start: The first moment of the range.
    ///   - end: The first moment after the range.
    ///   - now: The current time, whose unfinished day the average leaves out.
    ///   - calendar: The calendar of the days.
    /// - Returns: The sum of all days and the average of the finished days with data.
    public static func range(
        _ days: [HealthDayValue],
        from start: Date,
        to end: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> (total: Int, average: Int?) {
        let inside = days.filter { $0.date >= start && $0.date < end }
        return (Int(inside.reduce(0) { $0 + $1.value }.rounded()), average(of: inside, now: now, calendar: calendar))
    }

    /// Says whether an older page still has any data.
    public static func hasData(_ days: [HealthDayValue], count: Int, page: Int, now: Date, calendar: Calendar = .current) -> Bool {
        chartDays(days, count: count, page: page, now: now, calendar: calendar).contains { $0.value > 0 }
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
    /// Calls back when new steps arrive, also by waking the app in the background.
    func observeSteps(onChange: @escaping @MainActor @Sendable () async -> Void)
    /// Returns the steps of one day, one value per hour with data.
    func hourlySteps(on day: Date) async -> [HealthDayValue]
}

extension HealthDataSource {
    /// Sources without an hour breakdown show an empty day.
    public func hourlySteps(on day: Date) async -> [HealthDayValue] { [] }
}

/// The real connection to Apple Health.
@MainActor
public final class AppleHealthSource: HealthDataSource {
    private let store = HKHealthStore()
    private var stepObserver: HKObserverQuery?

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

    /// Watches the step count and asks Apple Health to wake the app about once an hour.
    ///
    /// The handler runs before the query is told it is done, so iOS keeps the app awake for it.
    public func observeSteps(onChange: @escaping @MainActor @Sendable () async -> Void) {
        guard isAvailable, stepObserver == nil else { return }
        let type = HKQuantityType(.stepCount)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            guard error == nil else {
                completion()
                return
            }
            let done = QueryCompletion(call: completion)
            Task { @MainActor in
                await onChange()
                done.call()
            }
        }
        stepObserver = query
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
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

    /// Returns the steps of one day, one value per hour with data.
    public func hourlySteps(on day: Date) async -> [HealthDayValue] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return await collect(.stepCount, unit: .count(), options: .cumulativeSum, from: start, to: min(end, .now), interval: DateComponents(hour: 1))
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
        return await collect(identifier, unit: unit, options: options, from: start, to: .now, interval: DateComponents(day: 1)).reversed()
    }

    /// Reads one value per interval between two moments.
    ///
    /// - Parameters:
    ///   - identifier: The kind of value.
    ///   - unit: The unit of the result.
    ///   - options: Sum or average.
    ///   - start: The first moment, also the anchor of the intervals.
    ///   - end: The last moment read.
    ///   - interval: The length of one bucket, such as a day or an hour.
    /// - Returns: The buckets with data, oldest first.
    private func collect(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from start: Date,
        to end: Date,
        interval: DateComponents
    ) async -> [HealthDayValue] {
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: range),
            options: options,
            anchorDate: start,
            intervalComponents: interval
        )
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var values: [HealthDayValue] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            let quantity = options == .cumulativeSum ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity { values.append(HealthDayValue(date: statistics.startDate, value: quantity.doubleValue(for: unit))) }
        }
        return values
    }
}

/// Carries Apple Health's completion call to the main actor. Apple Health allows calling it from any thread.
private struct QueryCompletion: @unchecked Sendable {
    let call: () -> Void
}

/// Keeps body data and workouts in step with Apple Health after the person allowed it.
@MainActor
public enum AppleHealthSync {
    public static let enabledKey = "lifify.appleHealth"
    public static let exportedKey = "lifify.appleHealthWorkouts"
    public static let weightDateKey = "lifify.appleHealthWeightDate"
    /// The days read for the step chart, so older weeks and months can be paged through.
    public static let summaryDays = 366

    /// The connection. Tests replace it.
    public static var source: any HealthDataSource = AppleHealthSource()
    /// What runs when Apple Health reports new steps. The app sets it at launch.
    public static var onStepChange: (@MainActor @Sendable () async -> Void)?

    /// Starts watching the steps once the person allowed Apple Health and a handler is set.
    public static func startStepUpdates() {
        guard isEnabled, let onStepChange else { return }
        source.observeSteps(onChange: onStepChange)
    }

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
        startStepUpdates()
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
    public static func summary(days: Int = summaryDays) async -> HealthSummary? {
        guard isEnabled else { return nil }
        return await source.summary(days: days)
    }

    /// Reads the hours of one day for the step chart's day view.
    public static func hourlySteps(on day: Date) async -> [HealthDayValue] {
        guard isEnabled else { return [] }
        return await source.hourlySteps(on: day)
    }

    /// The key of today's last read step count.
    public static let todayStepsKey = "lifify.appleHealthTodaySteps"
    /// The key of the time of that reading.
    public static let todayStepsDateKey = "lifify.appleHealthTodayStepsDate"

    /// Reads today's steps and keeps them for the widgets.
    public static func refreshTodaySteps(now: Date = .now) async {
        guard isEnabled else { return }
        let today = await source.summary(days: 1).steps.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
        AppDefaults.store.set(Int(today?.value.rounded() ?? 0), forKey: todayStepsKey)
        AppDefaults.store.set(now, forKey: todayStepsDateKey)
    }

    /// Today's last read steps with their time, or `nil` while Apple Health is off or not read today.
    public static func cachedTodaySteps(now: Date = .now) -> (count: Int, readAt: Date)? {
        guard isEnabled, let readAt = AppDefaults.store.object(forKey: todayStepsDateKey) as? Date,
              Calendar.current.isDate(readAt, inSameDayAs: now) else { return nil }
        return (AppDefaults.store.integer(forKey: todayStepsKey), readAt)
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
