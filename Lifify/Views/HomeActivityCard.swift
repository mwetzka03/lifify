import LififyCore
import LififyHealth
import SwiftData
import SwiftUI

/// Steps and planned trainings of the day, week, or month chosen in the home calendar.
///
/// Both follow the calendar: the trainings come from its events and their linked plans, so a
/// moved or deleted event changes this card too.
struct HomeActivityCard: View {
    let start: Date
    let end: Date
    let isSingleDay: Bool
    @EnvironmentObject private var workouts: WorkoutStore
    @Query private var events: [ChallengeCalendarEvent]
    @AppStorage(AppleHealthSync.enabledKey) private var healthEnabled = false
    @State private var steps = HealthSummary()

    var body: some View {
        let trainings = TrainingAgenda.items(events: events, plans: workouts.plans, sessions: workouts.sessions, from: start, to: end)
        if healthEnabled || !trainings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if healthEnabled { stepsRow }
                if healthEnabled && !trainings.isEmpty { Divider() }
                if !trainings.isEmpty { trainingRows(trainings) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .appGlassCard(radius: 18)
            .loadsSteps(into: $steps)
        }
    }

    /// The steps of the range: the count of a day, or the sum and daily average of a week or month.
    private var stepsRow: some View {
        let figures = StepStats.range(steps.steps, from: start, to: end, now: .now)
        return HStack {
            Label(L("Schritte", "Steps"), systemImage: "figure.walk")
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(figures.total.formatted())
                    .font(.headline)
                    .monospacedDigit()
                if !isSingleDay, let average = figures.average {
                    Text("Ø \(average.formatted()) \(L("pro Tag", "per day"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The trainings the calendar plans in the range.
    private func trainingRows(_ items: [TrainingAgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("Trainings", "Workouts"), systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.weight(.semibold))
            ForEach(items.prefix(8)) { item in
                HStack {
                    Text(isSingleDay ? AppDate.time(item.date) : AppDate.weekdayShort(item.date) + " " + AppDate.time(item.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: isSingleDay ? 58 : 82, alignment: .leading)
                    Text(item.planName)
                    Spacer()
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .appAccentForeground()
                }
            }
        }
    }
}

/// Loads the step history from Apple Health while the app is in front.
private struct StepLoader: ViewModifier {
    @Binding var summary: HealthSummary
    @AppStorage(AppleHealthSync.enabledKey) private var isEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: "\(isEnabled)\(scenePhase == .active)") {
            guard isEnabled, scenePhase == .active else { return }
            summary = await AppleHealthSync.summary() ?? HealthSummary()
        }
    }
}

extension View {
    /// Keeps a step summary filled from Apple Health.
    func loadsSteps(into summary: Binding<HealthSummary>) -> some View {
        modifier(StepLoader(summary: summary))
    }
}
