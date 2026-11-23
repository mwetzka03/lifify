import LififyCore
import LififyHealth
import SwiftUI

/// Steps, active energy, and resting pulse from Apple Health, as plain numbers.
struct AppleHealthCard: View {
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var summary = HealthSummary()

    var body: some View {
        Group {
            if isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Apple Health", systemImage: "heart.text.square")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        metric(L("Schritte", "Steps"), summary.steps, unit: "")
                        metric(L("Aktive Energie", "Active energy"), summary.activeEnergy, unit: " kcal")
                        metric(L("Ruhepuls", "Resting pulse"), summary.restingHeartRate, unit: " bpm")
                    }
                    if !summary.steps.isEmpty { recentSteps }
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

    /// The newest value of a metric.
    private func metric(_ title: String, _ values: [HealthDayValue], unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(values.first.map { "\(Int($0.value.rounded()).formatted())\(unit)" } ?? "–")
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

    /// The steps of the last days as a short list.
    private var recentSteps: some View {
        VStack(spacing: 3) {
            ForEach(summary.steps.dropFirst()) { day in
                HStack {
                    Text(AppDate.weekdayShort(day.date))
                    Spacer()
                    Text(Int(day.value.rounded()).formatted())
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
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
                    "Liest Gewicht, Schritte, aktive Energie und Ruhepuls und sichert beendete Trainings als Workouts. Die Daten bleiben auf dem Gerät.",
                    "Reads weight, steps, active energy, and resting pulse, and saves finished workouts. The data stays on this device."
                ))
        }
        .appGlassRow()
    }
}
