import Charts
import LififyCore
import LififyHealth
import SwiftUI

/// The steps from Apple Health under Training: a bar per day with the week and month averages.
struct StepsCard: View {
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = HealthSummary()
    @State private var showsMonth = false

    var body: some View {
        Group {
            if isEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L("Schritte", "Steps"), systemImage: "figure.walk")
                        .font(.headline)
                    figures
                    Picker(L("Zeitraum", "Range"), selection: $showsMonth) {
                        Text(L("7 Tage", "7 days")).tag(false)
                        Text(L("30 Tage", "30 days")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    chart
                    Text(L("Durchschnitte ohne heute und ohne Tage ohne Daten.", "Averages leave out today and days without data."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appGlassCard(radius: 18)
            }
        }
        .task(id: "\(isEnabled)\(scenePhase == .active)") {
            guard isEnabled, scenePhase == .active else { return }
            await AppleHealthSync.refreshWeight()
            summary = await AppleHealthSync.summary() ?? HealthSummary()
        }
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

    /// The bars of the chosen days with the matching average as a line.
    private var chart: some View {
        let days = StepStats.chartDays(summary.steps, count: showsMonth ? 30 : 7, now: .now)
        let average = showsMonth ? stats.monthAverage : stats.weekAverage
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
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
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
        } footer: {
            Text(failed
                ? L("Apple Health ist auf diesem Gerät nicht verfügbar.", "Apple Health is not available on this device.")
                : L(
                    "Liest Gewicht und Schritte und schreibt jedes beendete Training als Workout nach Apple Health. Die Daten bleiben auf dem Gerät.",
                    "Reads weight and steps and writes each finished workout to Apple Health. The data stays on this device."
                ))
        }
        .appGlassRow()
    }
}
