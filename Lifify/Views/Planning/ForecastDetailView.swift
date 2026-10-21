import SwiftData
import SwiftUI

struct ForecastDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    let item: ForecastListItem
    let period: ForecastPeriod
    @State private var chosen: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Art", "Type"), value: kindTitle)
                    LabeledContent(L("Datum", "Date"), value: AppDate.numeric(item.date))
                    LabeledContent(L("Betrag", "Amount"), value: Money.signed(cents: item.signedCents))
                }
                Section {
                    Text(L(
                        "Eine zugewiesene Buchung ersetzt diese Prognose für den ganzen Zeitraum. Die anderen Termine bleiben bestehen. Automatisch erkannte Buchungen gelten weiterhin.",
                        "An assigned transaction replaces this forecast for the whole period. The other dates stay. Bookings recognized automatically still apply."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    if candidates.isEmpty {
                        Text(L("In diesem Zeitraum liegt keine passende Buchung.", "This period has no matching transaction."))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(L("Buchung", "Transaction"), selection: $chosen) {
                            Text(L("Keine", "None")).tag(Optional<UUID>.none)
                            ForEach(candidates) { entry in
                                Text(choiceLabel(entry)).tag(Optional(entry.id))
                            }
                        }
                    }
                } header: {
                    Text(L("Buchung zuweisen", "Assign transaction"))
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Schließen", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Sichern", "Save")) {
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear { chosen = coveringEntryID }
        }
    }

    private var kindTitle: String {
        switch item.refKind {
        case .income: L("Einnahme", "Income")
        case .fixed: L("Fixkosten", "Fixed cost")
        case .transfer: L("Umbuchung", "Transfer")
        case .variable: L("Variable Kosten", "Variable cost")
        case .shopping: L("Einkaufszettel", "Shopping list")
        }
    }

    private var candidates: [LedgerEntry] {
        entries.filter { entry in
            guard period.contains(entry.date) else { return false }
            switch item.refKind {
            case .income:
                return entry.kind == .income && !BookingClassification.isRefund(entry)
            case .fixed, .variable, .shopping:
                return entry.kind == .expense
            case .transfer:
                return entry.kind == .transfer
            }
        }
    }

    private var coveringEntryID: UUID? {
        entries.first { entry in
            guard period.contains(entry.date), let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == item.refKind && link.id == item.sourceID
        }?.id
    }

    private func choiceLabel(_ entry: LedgerEntry) -> String {
        "\(entry.title) · \(AppDate.numeric(entry.date)) · \(Money.string(cents: abs(entry.amountCents)))"
    }

    private func apply() {
        let previous = entries.filter { entry in
            guard period.contains(entry.date), let link = ForecastPeriodLinkStore.link(for: entry.id) else { return false }
            return link.kind == item.refKind && link.id == item.sourceID
        }
        for entry in previous where entry.id != chosen {
            clearLink(entry.id)
        }
        guard let chosen else { return }
        ForecastPeriodLinkStore.assign(entryID: chosen, kind: item.refKind, forecastID: item.sourceID)
        switch item.kind {
        case .income:
            IncomeAssignmentStore.assign(entryID: chosen, to: item.sourceID)
        case .transfer:
            TransferForecastAssignmentStore.assign(entryID: chosen, forecastID: item.sourceID)
        case .expense, .variable, .shopping:
            break
        }
    }

    private func clearLink(_ entryID: UUID) {
        ForecastPeriodLinkStore.clear(entryID: entryID)
        switch item.kind {
        case .income:
            IncomeAssignmentStore.clear(entryID: entryID)
        case .transfer:
            TransferForecastAssignmentStore.clear(entryID: entryID)
        case .expense, .variable, .shopping:
            break
        }
    }
}
