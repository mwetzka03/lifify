import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// The spending of the last finished period compared with earlier ones.
struct PeriodReviewView: View {
    @Query private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    @Query private var costs: [FixedCost]
    @Query private var budgets: [VariableBudget]
    @Query private var pools: [BudgetPool]
    @Query private var forecasts: [IncomeForecast]
    @Query private var accounts: [Account]
    @AppStorage("dashboardPeriodMode") private var periodMode = DashboardPeriodMode.calendarMonth.rawValue

    /// The calculated review.
    private var review: PeriodReview? {
        PeriodReviewBuilder.make(
            .init(entries: entries, splits: splits, costs: costs, budgets: budgets, pools: pools),
            periods: PeriodReviewBuilder.periods(mode: periodMode, entries: entries, forecasts: forecasts, accounts: accounts)
        )
    }

    var body: some View {
        Group {
            if let review {
                reviewList(review)
            } else {
                ContentUnavailableView(
                    L("Noch kein Rückblick", "No review yet"),
                    systemImage: "calendar.badge.clock",
                    description: Text(L("Der Rückblick erscheint, sobald ein Zeitraum abgeschlossen ist.", "The review appears once a period has ended."))
                )
            }
        }
        .appGlassList()
        .navigationTitle(L("Zeitraumsrückblick", "Period review"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The summary and the categories.
    private func reviewList(_ review: PeriodReview) -> some View {
        List {
            Section {
                LabeledContent(L("Zeitraum", "Period"), value: AppDate.range(from: review.period.start, to: review.period.end))
                LabeledContent(L("Ausgaben", "Expenses"), value: Money.string(cents: review.totalCents))
                if review.comparedPeriods > 0 {
                    LabeledContent(L("Durchschnitt", "Average"), value: Money.string(cents: review.averageTotalCents))
                }
            } footer: {
                Text(comparisonNote(review.comparedPeriods))
            }
            .appGlassRow()
            Section(L("Nach Kategorie", "By category")) {
                ForEach(review.lines) { line in
                    categoryRow(line, compares: review.comparedPeriods > 0)
                }
            }
            .appGlassRow()
        }
    }

    /// Explains what the average is based on.
    private func comparisonNote(_ count: Int) -> String {
        switch count {
        case 0: L("Für einen Vergleich fehlen frühere Zeiträume.", "Earlier periods are needed for a comparison.")
        case 1, 2: L("Verglichen mit nur \(count) früheren Zeiträumen.", "Compared with only \(count) earlier periods.")
        default: L("Verglichen mit den letzten \(count) Zeiträumen.", "Compared with the last \(count) periods.")
        }
    }

    /// One category. Spending more than usual is red, less is green.
    private func categoryRow(_ line: PeriodReviewLine, compares: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                if compares {
                    Text("\(L("Durchschnitt", "Average")) \(Money.string(cents: line.averageCents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.string(cents: line.spentCents))
                if compares {
                    Text(Money.signed(cents: line.differenceCents))
                        .font(.caption.bold())
                        .foregroundStyle(line.differenceCents > 0 ? .red : (line.differenceCents < 0 ? .green : .secondary))
                }
            }
        }
    }
}

/// Repeated payments that can become fixed costs, at the top of the fixed costs.
///
/// The section starts folded so it never pushes the costs out of view.
struct SubscriptionSuggestionSection: View {
    @Environment(\.modelContext) private var context
    let entries: [LedgerEntry]
    let costs: [FixedCost]
    @State private var isOpen = false
    @State private var revision = 0

    var body: some View {
        let _ = revision
        let suggestions = SubscriptionDetector.suggestions(entries: entries, costs: costs)
        if !suggestions.isEmpty {
            Section {
                Button {
                    withAnimation { isOpen.toggle() }
                } label: {
                    HStack {
                        Label("\(L("Abo-Vorschläge", "Subscriptions")) (\(suggestions.count))", systemImage: "repeat")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if isOpen {
                    ForEach(suggestions) { suggestionRow($0) }
                }
            }
            .appGlassRow()
        }
    }

    /// One suggestion with its two answers.
    private func suggestionRow(_ suggestion: SubscriptionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.title).font(.headline)
                Spacer(minLength: 12)
                Text(Money.string(cents: suggestion.amountCents)).font(.headline)
            }
            Text("\(suggestion.cadence.label) · \(suggestion.occurrences) \(L("Zahlungen", "payments")) · \(L("zuletzt", "last")) \(AppDate.numeric(suggestion.lastDate))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(L("Als Fixkosten anlegen", "Add as fixed cost")) {
                    SubscriptionDetector.adopt(suggestion, entries: entries, context: context)
                    revision += 1
                }
                .buttonStyle(.bordered)
                Button(L("Ablehnen", "Dismiss"), role: .destructive) {
                    SubscriptionDetector.reject(suggestion)
                    revision += 1
                }
                .buttonStyle(.borderless)
            }
            .appAccentTint()
        }
        .padding(.vertical, 4)
    }
}
