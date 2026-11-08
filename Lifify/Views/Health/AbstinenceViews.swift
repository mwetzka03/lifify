import SwiftData
import SwiftUI

struct AbstinenceSummary: View {
    let challenge: ChallengeItem
    @Environment(\.modelContext) private var context
    @AppStorage(AbstinenceSettings.revisionKey) private var revision = 0
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = AppClock.now
            let _ = revision
            let _ = developerMode
            let _ = developerDay
            summary(now)
                .task(id: settleToken(now)) {
                    AbstinenceService.settle(context: context)
                }
        }
    }

    private func summary(_ now: Date) -> some View {
        let start = challenge.startDate ?? challenge.createdAt
        let elapsed = AbstinenceRules.elapsed(from: start, to: now)
        let difficulty = AbstinenceSettings.difficulty(for: challenge.id)
        return HStack(spacing: 12) {
            Image(systemName: IconPreferenceStore.icon(for: challenge.id, fallback: "lungs.fill"))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .foregroundStyle(.primary)
                Text("\(difficulty.label) · \(AbstinenceClockText.string(elapsed))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let next = AbstinenceMilestone.allCases.first(where: { now < $0.due(from: start) }) {
                    Text(L("Nächster Bonus: \(next.label)", "Next bonus: \(next.label)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L("Alle Boni erreicht", "Every bonus reached"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            CoinAmountView(amount: challenge.rewardCoins, showsPlus: true)
                .font(.caption)
        }
    }

    private func settleToken(_ now: Date) -> String {
        let start = challenge.startDate ?? challenge.createdAt
        let reached = AbstinenceRules.reached(start: start, now: now).map(\.rawValue).joined(separator: ",")
        let days = AbstinenceRules.clock(AbstinenceRules.elapsed(from: start, to: now)).days
        return "\(days):\(reached)"
    }
}

enum AbstinenceClockText {
    static func string(_ interval: TimeInterval) -> String {
        let clock = AbstinenceRules.clock(interval)
        let time = String(format: "%02d:%02d:%02d", clock.hours, clock.minutes, clock.seconds)
        guard clock.days > 0 else { return time }
        let unit = clock.days == 1 ? L("Tag", "day") : L("Tage", "days")
        return "\(clock.days) \(unit) \(time)"
    }
}

struct AbstinenceDetailView: View {
    let challengeID: UUID
    @Environment(\.modelContext) private var context
    @Query private var challenges: [ChallengeItem]
    @AppStorage(AbstinenceSettings.revisionKey) private var revision = 0
    @AppStorage(AppClock.modeKey) private var developerMode = false
    @AppStorage(AppClock.dayKey) private var developerDay = 0.0
    @State private var confirmingRelapse = false
    @State private var edited: ChallengeItem?

    private var challenge: ChallengeItem? {
        challenges.first { $0.id == challengeID }
    }

    var body: some View {
        Group {
            if let challenge {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = AppClock.now
                    let _ = revision
                    let _ = developerMode
                    let _ = developerDay
                    detail(challenge, now: now)
                        .task(id: settleToken(challenge, now)) {
                            AbstinenceService.settle(context: context)
                        }
                }
                .navigationTitle(challenge.title)
                .toolbar {
                    Button(L("Bearbeiten", "Edit")) { edited = challenge }
                }
                .sheet(item: $edited) { ChallengeForm(challenge: $0) }
                .confirmationDialog(
                    L("Timer zurücksetzen?", "Reset the timer?"),
                    isPresented: $confirmingRelapse,
                    titleVisibility: .visible
                ) {
                    Button(L("Zurücksetzen", "Reset"), role: .destructive) {
                        AbstinenceService.relapse(challenge, context: context)
                    }
                    Button(L("Abbrechen", "Cancel"), role: .cancel) {}
                } message: {
                    Text(L(
                        "Die Zeit startet neu. Coins, die du schon bekommen hast, bleiben. Die Boni kannst du in diesem Lauf wieder erreichen.",
                        "The time starts again. Coins you already received stay. You can reach the bonuses again on this run."
                    ))
                }
            } else {
                ContentUnavailableView(L("Abstinenz nicht gefunden", "Abstinence not found"), systemImage: "lungs.fill")
            }
        }
    }

    private func detail(_ challenge: ChallengeItem, now: Date) -> some View {
        let start = challenge.startDate ?? challenge.createdAt
        let elapsed = AbstinenceRules.elapsed(from: start, to: now)
        let difficulty = AbstinenceSettings.difficulty(for: challenge.id)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AbstinenceClockText.string(elapsed))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(difficulty.label)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(L("Pro Tag", "Per day"))
                        CoinAmountView(amount: challenge.rewardCoins, showsPlus: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            Section {
                ForEach(AbstinenceMilestone.allCases) { milestone in
                    let reached = now >= milestone.due(from: start)
                    let coins = AbstinenceRules.bonusCoins(
                        base: challenge.rewardCoins,
                        multiplier: AbstinenceSettings.multiplier(for: difficulty, milestone: milestone)
                    )
                    HStack {
                        Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(reached ? .green : .secondary)
                        Text(milestone.label)
                        Spacer()
                        CoinAmountView(amount: coins, showsPlus: true)
                            .foregroundStyle(reached ? .primary : .secondary)
                    }
                }
            } header: {
                Text(L("Boni", "Bonuses"))
            } footer: {
                Text(L(
                    "Ein Bonus ist der Faktor dieser Stufe mal die Coins pro Tag. Es zählt jede erreichte Stufe, nicht nur die höchste.",
                    "A bonus is that step’s factor times the coins per day. Every reached step counts, not only the highest one."
                ))
            }
            Section {
                Button(L("Rückfall", "Relapse"), role: .destructive) {
                    confirmingRelapse = true
                }
            }
        }
    }

    private func settleToken(_ challenge: ChallengeItem, _ now: Date) -> String {
        let start = challenge.startDate ?? challenge.createdAt
        let reached = AbstinenceRules.reached(start: start, now: now).map(\.rawValue).joined(separator: ",")
        let days = AbstinenceRules.clock(AbstinenceRules.elapsed(from: start, to: now)).days
        return "\(days):\(reached)"
    }
}
