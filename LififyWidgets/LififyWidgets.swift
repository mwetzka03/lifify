import ActivityKit
import AppIntents
import LififyCore
import SwiftUI
import WidgetKit

/// All widgets of the app.
@main
struct LififyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        TodayWidget()
        CoinsWidget()
        DepotWidget()
        TrainingWidget()
        OverviewWidget()
        BudgetRingLockWidget()
        NextChallengeLockWidget()
        CoinsLockWidget()
        WorkoutLiveActivity()
    }
}

/// One moment of a widget's timeline.
struct LififyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Shows the stored snapshot and refreshes at midnight, when the day's list changes.
struct LififyProvider: TimelineProvider {
    /// A neutral placeholder.
    func placeholder(in context: Context) -> LififyEntry {
        LififyEntry(date: .now, snapshot: nil)
    }

    /// The current data for the widget gallery.
    func getSnapshot(in context: Context, completion: @escaping (LififyEntry) -> Void) {
        completion(LififyEntry(date: .now, snapshot: WidgetStore.read()))
    }

    /// One entry now and one at the start of tomorrow.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LififyEntry>) -> Void) {
        let snapshot = WidgetStore.read()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let entries = [LififyEntry(date: .now, snapshot: snapshot), LififyEntry(date: midnight, snapshot: snapshot)]
        let next = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

/// Books a challenge from the widget. The app applies it with all its rules when it next runs.
struct WidgetCheckOffIntent: AppIntent {
    static var title: LocalizedStringResource { "Challenge abhaken" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Challenge")
    var challengeID: String

    /// Creates an empty intent for the system.
    init() {}

    /// Creates the intent of one challenge.
    init(challengeID: UUID) {
        self.challengeID = challengeID.uuidString
    }

    /// Queues the check-off and updates the widgets.
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: challengeID) {
            WidgetStore.enqueue(WidgetCheckOff(challengeID: id, date: .now))
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Picks the text in the app's language.
private func text(_ snapshot: WidgetSnapshot?, _ german: String, _ english: String) -> String {
    snapshot?.isGerman == false ? english : german
}

/// Formats cents as euros.
private func euros(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
}

/// The accent of the chosen style.
private func accent(_ snapshot: WidgetSnapshot?) -> Color {
    switch snapshot?.paletteRaw {
    case "blue": Color(red: 0.31, green: 0.49, blue: 0.67)
    case "bordeaux": Color(red: 0.55, green: 0.18, blue: 0.27)
    case "violet": Color(red: 0.48, green: 0.38, blue: 0.66)
    default: Color(red: 0.18, green: 0.62, blue: 0.48)
    }
}

/// Shown instead of amounts while the Finance lock hides them.
private struct LockedAmounts: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill").font(.title2)
            Text(text(snapshot, "Gesperrt", "Locked")).font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The budget ring with the remaining amount.
private struct BudgetRing: View {
    let finance: WidgetFinance
    let tint: Color

    var body: some View {
        let over = finance.remainingCents < 0
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: 9)
            Circle()
                .trim(from: 0, to: over ? 1 : finance.usedFraction)
                .stroke(over ? Color.red : tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(euros(finance.remainingCents))
                .font(.caption2.bold())
                .foregroundStyle(over ? .red : .primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 12)
        }
    }
}

/// One open challenge, with a check-off button or a link to its training.
private struct ChallengeLine: View {
    let challenge: WidgetChallenge
    let tint: Color

    var body: some View {
        if challenge.canCheckOff {
            Button(intent: WidgetCheckOffIntent(challengeID: challenge.id)) {
                row(symbol: "circle")
            }
            .buttonStyle(.plain)
        } else if let planID = challenge.planID, let url = WidgetRoute.url(plan: planID) {
            Link(destination: url) { row(symbol: "figure.strengthtraining.traditional") }
        } else {
            row(symbol: "lock")
        }
    }

    /// The symbol with the title.
    private func row(symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(challenge.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

/// The day's open challenges.
private struct ChallengeList: View {
    let entry: LififyEntry
    let limit: Int

    var body: some View {
        let items = entry.snapshot?.challenges(on: entry.date) ?? []
        VStack(alignment: .leading, spacing: 5) {
            Text(text(entry.snapshot, "Heute", "Today")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if items.isEmpty {
                Text(text(entry.snapshot, "Alles erledigt", "All done")).font(.caption)
            }
            ForEach(items.prefix(limit)) { ChallengeLine(challenge: $0, tint: accent(entry.snapshot)) }
        }
    }
}

/// Applies the widget background.
private extension View {
    /// The system's container background.
    func widgetSurface() -> some View {
        containerBackground(.fill.tertiary, for: .widget)
    }
}

/// Today's remaining budget as a ring.
struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyBudget", provider: LififyProvider()) { entry in
            Group {
                if let finance = entry.snapshot?.finance {
                    VStack(spacing: 6) {
                        BudgetRing(finance: finance, tint: accent(entry.snapshot))
                        if let daily = finance.dailyCents {
                            Text("\(text(entry.snapshot, "Pro Tag", "Per day")) \(euros(daily))")
                                .font(.caption2)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }
                } else {
                    LockedAmounts(snapshot: entry.snapshot)
                }
            }
            .widgetSurface()
        }
        .configurationDisplayName("Tagesbudget")
        .description("Restbudget und Betrag pro Tag.")
        .supportedFamilies([.systemSmall])
    }
}

/// Today's challenges with the next slot.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyToday", provider: LififyProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                ChallengeList(entry: entry, limit: 4)
                Spacer(minLength: 0)
                if let slot = entry.snapshot?.nextSlot {
                    Label("\(slot.date.formatted(date: .omitted, time: .shortened)) \(slot.title)", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetSurface()
        }
        .configurationDisplayName("Heute")
        .description("Offene Challenges zum Abhaken und der nächste Termin.")
        .supportedFamilies([.systemMedium])
    }
}

/// The wallet and the longest streak.
struct CoinsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyCoins", provider: LififyProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Label("Coins", systemImage: "bitcoinsign.circle").font(.caption).foregroundStyle(.secondary)
                Text("\(entry.snapshot?.coins ?? 0)")
                    .font(.title.bold())
                    .foregroundStyle(entry.snapshot?.isShopLocked == true ? .red : .primary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if entry.snapshot?.isShopLocked == true {
                    Text(text(entry.snapshot, "Shop gesperrt", "Shop locked")).font(.caption2.bold()).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                Label("\(entry.snapshot?.longestStreak ?? 0)", systemImage: "flame.fill").font(.caption).foregroundStyle(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetSurface()
        }
        .configurationDisplayName("Coins & Streak")
        .description("Wallet und längster laufender Streak.")
        .supportedFamilies([.systemSmall])
    }
}

/// The depot value with today's change.
struct DepotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyDepot", provider: LififyProvider()) { entry in
            Group {
                if let finance = entry.snapshot?.finance {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text(entry.snapshot, "Depot", "Portfolio")).font(.caption).foregroundStyle(.secondary)
                        Text(euros(finance.depotCents)).font(.title3.bold()).minimumScaleFactor(0.5).lineLimit(1)
                        if let change = finance.depotChangeCents {
                            Text("\(change > 0 ? "+" : "")\(euros(change))")
                                .font(.caption.bold())
                                .foregroundStyle(change < 0 ? .red : (change > 0 ? .green : .secondary))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LockedAmounts(snapshot: entry.snapshot)
                }
            }
            .widgetSurface()
        }
        .configurationDisplayName("Depot")
        .description("Depotwert und Veränderung zum Vortag.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The next training with its slot.
private struct TrainingBlock: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text(snapshot, "Nächstes Training", "Next workout"), systemImage: "figure.strengthtraining.traditional")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let training = snapshot?.nextTraining {
                Text(training.title).font(.headline).lineLimit(2)
                Text(training.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(text(snapshot, "Kein Termin", "Nothing planned")).font(.caption)
            }
        }
    }
}

/// Today's steps with the time they were read, because the widget cannot read Apple Health itself.
private struct StepsLine: View {
    let steps: WidgetSteps
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(steps.count.formatted(), systemImage: "figure.walk")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text("\(text(snapshot, "Schritte, Stand", "steps as of")) \(steps.readAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// The next training, opened with a tap.
struct TrainingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyTraining", provider: LififyProvider()) { entry in
            TrainingBlock(snapshot: entry.snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(entry.snapshot?.nextTraining?.planID.flatMap(WidgetRoute.url(plan:)))
                .widgetSurface()
        }
        .configurationDisplayName("Nächstes Training")
        .description("Plan und Termin. Ein Tipp öffnet das Training.")
        .supportedFamilies([.systemSmall])
    }
}

/// Budget, challenges, and the next training.
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyOverview", provider: LififyProvider()) { entry in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Group {
                        if let finance = entry.snapshot?.finance {
                            BudgetRing(finance: finance, tint: accent(entry.snapshot))
                        } else {
                            LockedAmounts(snapshot: entry.snapshot)
                        }
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 10) {
                        TrainingBlock(snapshot: entry.snapshot)
                        if let steps = entry.snapshot?.steps, Calendar.current.isDate(steps.readAt, inSameDayAs: entry.date) {
                            StepsLine(steps: steps, snapshot: entry.snapshot)
                        }
                    }
                    Spacer(minLength: 0)
                }
                ChallengeList(entry: entry, limit: 7)
                Spacer(minLength: 0)
            }
            .widgetSurface()
        }
        .configurationDisplayName("Überblick")
        .description("Budgetring, Challenges von heute und nächstes Training.")
        .supportedFamilies([.systemLarge])
    }
}

/// The used budget as a round Lock Screen gauge.
struct BudgetRingLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyBudgetLock", provider: LififyProvider()) { entry in
            Group {
                if let finance = entry.snapshot?.finance {
                    Gauge(value: finance.usedFraction) {
                        Text("%")
                    } currentValueLabel: {
                        Text("\(Int((finance.usedFraction * 100).rounded()))")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                } else {
                    Image(systemName: "lock.fill")
                }
            }
            .widgetSurface()
        }
        .configurationDisplayName("Budget")
        .description("Verbrauchtes Budget in Prozent.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// The next open challenge on the Lock Screen.
struct NextChallengeLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyNextLock", provider: LififyProvider()) { entry in
            let items = entry.snapshot?.challenges(on: entry.date) ?? []
            VStack(alignment: .leading, spacing: 1) {
                Text(text(entry.snapshot, "Nächste Challenge", "Next challenge")).font(.caption2)
                Text(items.first?.title ?? text(entry.snapshot, "Alles erledigt", "All done"))
                    .font(.headline)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetSurface()
        }
        .configurationDisplayName("Nächste Challenge")
        .description("Die nächste offene Challenge.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// The wallet as one Lock Screen line.
struct CoinsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LififyCoinsLock", provider: LififyProvider()) { entry in
            Text("\(entry.snapshot?.coins ?? 0) Coins")
                .widgetSurface()
        }
        .configurationDisplayName("Coins")
        .description("Der Stand des Wallets.")
        .supportedFamilies([.accessoryInline])
    }
}

/// The running training on the Lock Screen and in the Dynamic Island.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(context.attributes.planName).font(.headline)
                    Spacer()
                    Text(context.attributes.startedAt, style: .timer).monospacedDigit()
                }
                Text("\(context.state.exercise) · \(context.state.setNumber)/\(context.state.setCount)")
                    .font(.subheadline)
                restLine(context.state)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.planName).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer).font(.caption).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(context.state.exercise) · \(context.state.setNumber)/\(context.state.setCount)")
                        restLine(context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
            } compactTrailing: {
                compactTime(context)
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional")
            }
        }
    }

    /// The rest countdown, while a rest is running.
    @ViewBuilder
    private func restLine(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let end = state.restEndsAt, end > .now {
            Label {
                Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .font(.caption)
        }
    }

    /// The rest time, or the session time without a rest.
    @ViewBuilder
    private func compactTime(_ context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        if let end = context.state.restEndsAt, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true).monospacedDigit().frame(width: 44)
        } else {
            Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 44)
        }
    }
}
