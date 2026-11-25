import Charts
import LififyCore
import LififyHealth
import SwiftUI

/// The steps from Apple Health under Training: bars per hour of a day, or per day of a week or month, with averages.
struct StepsCard: View {
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    @Environment(\.colorScheme) private var scheme
    @State private var summary = HealthSummary()
    @State private var range = StepChartRange.week
    @State private var page = 0
    @State private var hours: [HealthDayValue] = []

    var body: some View {
        Group {
            if isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Schritte", "Steps"), systemImage: "figure.walk")
                        .font(.headline)
                    figures
                    Picker(L("Zeitraum", "Range"), selection: $range) {
                        Text(L("Tag", "Day")).tag(StepChartRange.day)
                        Text(L("7 Tage", "7 days")).tag(StepChartRange.week)
                        Text(L("30 Tage", "30 days")).tag(StepChartRange.month)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: range) { page = 0 }
                    pageHeader
                    Group {
                        if range == .day { hourChart } else { chart }
                    }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 24).onEnded(swiped))
                    Text(L("Wischen zeigt frühere Zeiträume. Durchschnitte ohne heute und ohne Tage ohne Daten.", "Swipe for earlier ranges. Averages leave out today and days without data."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appGlassCard(radius: 18)
            }
        }
        .loadsSteps(into: $summary)
        .task(id: range == .day ? page : -1) {
            guard range == .day else { return }
            hours = await AppleHealthSync.hourlySteps(on: shownDay)
        }
        .task { await AppleHealthSync.refreshWeight() }
    }

    private var stats: StepStats {
        StepStats.make(summary.steps, now: .now)
    }

    private var accent: Color {
        AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
    }

    /// Today, the averages, and the best day.
    private var figures: some View {
        HStack(alignment: .top, spacing: 12) {
            figure(L("Heute", "Today"), stats.today)
            figure(L("Ø 7 Tage", "Avg 7 days"), stats.weekAverage)
            figure(L("Ø 30 Tage", "Avg 30 days"), stats.monthAverage)
            figure(stats.best.map { "\(L("Bester", "Best")) \(AppDate.dayMonth($0.date))" } ?? L("Bester Tag", "Best day"),
                   stats.best.map { Int($0.value.rounded()) })
        }
    }

    /// One number with its label.
    private func figure(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { $0.formatted() } ?? "–")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsMonth: Bool { range == .month }

    private var pageLength: Int { range == .day ? 1 : (showsMonth ? 30 : 7) }

    /// The day of the day view.
    private var shownDay: Date {
        Calendar.current.date(byAdding: .day, value: -page, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    private var pageDays: [HealthDayValue] {
        StepStats.chartDays(summary.steps, count: pageLength, page: page, now: .now)
    }

    /// The shown range with arrows that page like the swipe.
    private var pageHeader: some View {
        let days = pageDays
        return HStack {
            Button { page += 1 } label: { Image(systemName: "chevron.left") }
                .disabled(!StepStats.hasData(summary.steps, count: pageLength, page: page + 1, now: .now))
            Spacer()
            Text(pageTitle(days))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Button { page -= 1 } label: { Image(systemName: "chevron.right") }
                .disabled(page == 0)
        }
        .buttonStyle(.borderless)
        .appAccentTint()
    }

    /// The dates of the page, or for one day its date and total.
    private func pageTitle(_ days: [HealthDayValue]) -> String {
        guard range == .day else {
            return "\(AppDate.dayMonth(days.first?.date ?? .now)) – \(AppDate.dayMonth(days.last?.date ?? .now))"
        }
        let total = Int(hours.reduce(0) { $0 + $1.value }.rounded())
        return "\(AppDate.weekdayShort(shownDay)) \(AppDate.dayMonth(shownDay)) · \(total.formatted()) \(L("Schritte", "steps"))"
    }

    /// The bars of the hours of the shown day.
    private var hourChart: some View {
        Chart {
            ForEach(StepStats.hourly(hours, on: shownDay)) { hour in
                BarMark(x: .value(L("Stunde", "Hour"), hour.date, unit: .hour), y: .value(L("Schritte", "Steps"), hour.value))
                    .foregroundStyle(accent.gradient)
                    .cornerRadius(2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(AppDate.time(date)) }
                }
            }
        }
        .frame(height: 160)
    }

    /// A swipe to the right shows older days, to the left newer ones.
    private func swiped(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        withAnimation {
            if value.translation.width > 0, StepStats.hasData(summary.steps, count: pageLength, page: page + 1, now: .now) {
                page += 1
            } else if value.translation.width < 0, page > 0 {
                page -= 1
            }
        }
    }

    /// The bars of the shown page with its average as a line.
    private var chart: some View {
        let days = pageDays
        let average = StepStats.average(of: days, now: .now)
        return Chart {
            ForEach(days) { day in
                BarMark(x: .value(L("Tag", "Day"), day.date, unit: .day), y: .value(L("Schritte", "Steps"), day.value))
                    .foregroundStyle(accent.gradient)
                    .cornerRadius(3)
            }
            if let average {
                RuleMark(y: .value("Ø", average))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Ø \(average.formatted())").font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: showsMonth ? 7 : 1)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(showsMonth ? AppDate.dayMonth(date) : AppDate.weekdayShort(date))
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

/// The switch of the Apple Health connection.
struct AppleHealthSection: View {
    @Environment(\.modelContext) private var context
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
    @AppStorage(StepChallenge.goalKey) private var stepGoal = 0
    @State private var failed = false

    var body: some View {
        Section {
            Toggle("Apple Health", isOn: Binding(
                get: { isEnabled },
                set: { wanted in
                    guard wanted else {
                        isEnabled = false
                        return
                    }
                    Task { failed = !(await AppleHealthSync.enable()) }
                }
            ))
            StepGoalField()
        } footer: {
            Text(failed
                ? L("Apple Health ist auf diesem Gerät nicht verfügbar.", "Apple Health is not available on this device.")
                : L(
                    "Liest Gewicht und Schritte und schreibt jedes beendete Training als Workout nach Apple Health. Mit einem Schrittziel gibt es eine Challenge mit \(StepChallenge.rewardCoins) Coins pro Tag, Streak und Freezes; 0 schaltet sie ab. Die Daten bleiben auf dem Gerät.",
                    "Reads weight and steps and writes each finished workout to Apple Health. A step goal adds a challenge with \(StepChallenge.rewardCoins) coins a day, streak, and freezes; 0 turns it off. The data stays on this device."
                ))
        }
        .appGlassRow()
        .onChange(of: isEnabled) { StepChallenge.sync(context: context) }
        .onChange(of: stepGoal) { StepChallenge.sync(context: context) }
    }
}

/// The daily step goal, shared by setup and settings. 0 means no goal.
struct StepGoalField: View {
    @AppStorage(StepChallenge.goalKey) private var stepGoal = 0

    var body: some View {
        HStack {
            Text(L("Schrittziel", "Step goal"))
            Spacer()
            TextField(StepChallenge.suggestedGoal.formatted(), value: $stepGoal, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(L("pro Tag", "a day"))
                .foregroundStyle(.secondary)
        }
    }
}

/// The ranges of the step chart.
enum StepChartRange: Hashable {
    case day, week, month
}
