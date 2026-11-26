import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// Creates a fixed cost from a booking: the person picks which payments of the same payee belong to it.
///
/// Amounts may differ between the payments. The payee is remembered, so later imports assign its new
/// bookings on their own (`FixedCostFromBooking`).
struct FixedCostFromBookingView: View {
    let source: LedgerEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [LedgerEntry]
    @State private var draft: FixedCostDraft
    @State private var chosen: Set<UUID>
    @State private var related: [LedgerEntry] = []

    /// Starts with the values of the booking itself until the related payments are loaded.
    init(source: LedgerEntry) {
        self.source = source
        _draft = State(initialValue: FixedCostFromBooking.suggestedDraft(name: source.title, source: source, chosen: [source]))
        _chosen = State(initialValue: [source.id])
    }

    var body: some View {
        NavigationStack {
            AppForm {
                Section {
                    FixedCostFields(draft: $draft)
                }
                Section {
                    ForEach(related) { entry in
                        bookingToggle(entry)
                    }
                } header: {
                    Text(L("Zugehörige Buchungen", "Related bookings"))
                } footer: {
                    Text(L(
                        "Gleicher Empfänger oder gleiche IBAN, auch mit anderem Betrag. Neue Buchungen dieses Empfängers werden beim Import automatisch zugeordnet und tragen das Symbol.",
                        "Same payee or IBAN, also with a different amount. New bookings of this payee are assigned on import and carry the icon."
                    ))
                }
            }
            .navigationTitle(L("Als Fixkosten anlegen", "Add as fixed cost"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Anlegen", "Create"), action: create)
                        .disabled(!draft.isComplete)
                }
            }
            .task {
                related = FixedCostFromBooking.related(to: source, in: entries)
                chosen = Set(related.map(\.id))
                // The other payments refine rhythm and first date; name and icon stay as the person sees them.
                let suggested = FixedCostFromBooking.suggestedDraft(name: draft.name, source: source, chosen: related)
                draft.cadence = suggested.cadence
                draft.firstDate = suggested.firstDate
                draft.amountText = suggested.amountText
                draft.day = suggested.day
            }
        }
    }

    /// One payment with a check mark that says whether it belongs to the fixed cost.
    private func bookingToggle(_ entry: LedgerEntry) -> some View {
        Button {
            if chosen.contains(entry.id) { chosen.remove(entry.id) } else { chosen.insert(entry.id) }
        } label: {
            HStack {
                Image(systemName: chosen.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .appAccentForeground()
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).foregroundStyle(.primary).lineLimit(1)
                    Text(AppDate.numeric(entry.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(cents: entry.amountCents))
                    .foregroundStyle(BookingClassification.differenceColor(entry.amountCents))
            }
        }
        .buttonStyle(.plain)
        .disabled(entry.id == source.id)
    }

    /// Creates the fixed cost from the chosen bookings and closes the sheet.
    private func create() {
        guard let cost = draft.save(into: nil, context: context) else { return }
        let picked = related.filter { chosen.contains($0.id) }
        FixedCostFromBooking.link(cost: cost, source: source, chosen: picked, context: context)
        dismiss()
    }
}

/// Links an income to an earlier expense as its refund.
///
/// Expenses of the same payee or IBAN stand in their own box above all others, so the order explains itself.
struct RefundLinkPicker: View {
    let income: LedgerEntry
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]

    var body: some View {
        let groups = RefundCandidates.groups(for: income, in: entries)
        NavigationStack {
            AppForm {
                Section {
                    if groups.suggested.isEmpty {
                        Text(L("Keine Ausgabe mit demselben Namen oder derselben IBAN.", "No expense with the same name or IBAN."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups.suggested) { expenseButton($0) }
                } header: {
                    Text(L("Vorschläge", "Suggestions"))
                } footer: {
                    Text(L("Gleicher Name oder gleiche IBAN wie die Einnahme.", "Same name or IBAN as the income."))
                }
                Section {
                    ForEach(groups.others) { expenseButton($0) }
                } header: {
                    Text(L("Alle Ausgaben", "All expenses"))
                } footer: {
                    Text(L(
                        "Die Einnahme zählt danach als Rückerstattung dieser Ausgabe. Ein späterer Import ändert die Verknüpfung nicht.",
                        "The income then counts as a refund of this expense. A later import does not change the link."
                    ))
                }
            }
            .navigationTitle(L("Ausgabe wählen", "Choose expense"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Abbrechen", "Cancel")) { dismiss() }
                }
            }
        }
    }

    /// One expense that links the income to it when tapped.
    private func expenseButton(_ expense: LedgerEntry) -> some View {
        Button {
            RefundLinkStore.link(refundID: income.id, to: expense.id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.title).foregroundStyle(.primary).lineLimit(1)
                    Text(AppDate.numeric(expense.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(cents: expense.amountCents))
                    .foregroundStyle(BookingClassification.differenceColor(expense.amountCents))
            }
        }
        .buttonStyle(.plain)
    }
}
