import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// Shows bookings that came from an import or a bank notice with their assignment, so the person can
/// keep it or pick another fixed cost, variable cost, or none.
///
/// "Done" takes the shown bookings off the list; "Later" keeps them for the next time.
struct AssignmentReviewView: View {
    /// The sources to show, in this order.
    let sources: [AssignmentInbox.Source]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date) private var entries: [LedgerEntry]
    @Query(sort: \FixedCost.name) private var fixedCosts: [FixedCost]
    @Query(sort: \VariableBudget.name) private var budgets: [VariableBudget]
    @Query(sort: \BudgetPool.name) private var pools: [BudgetPool]
    @State private var shown: [AssignmentInbox.Source: [LedgerEntry]] = [:]
    /// Changes when a pool changes, because pools live in splits the rows do not observe.
    @State private var revision = 0

    var body: some View {
        NavigationStack {
            AppForm {
                ForEach(sources, id: \.self) { source in
                    if let rows = shown[source], !rows.isEmpty {
                        Section {
                            ForEach(rows) { row($0) }
                        } header: {
                            Text(title(of: source))
                        } footer: {
                            Text(footer(of: source))
                        }
                    }
                }
            }
            .navigationTitle(L("Zuordnungen prüfen", "Check assignments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Später", "Later")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig", "Done")) {
                        AssignmentInbox.clear(shown.values.flatMap { $0.map(\.id) })
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    /// Takes the waiting bookings once, so a changed assignment does not move a row away.
    private func load() {
        var result: [AssignmentInbox.Source: [LedgerEntry]] = [:]
        for source in sources {
            result[source] = AssignmentInbox.pending(source, in: entries)
        }
        shown = result
    }

    /// One booking with its amount and the assignment picker.
    private func row(_ entry: LedgerEntry) -> some View {
        _ = revision
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).lineLimit(2)
                    Text(AppDate.numeric(entry.date)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.string(cents: entry.amountCents))
                    .foregroundStyle(BookingClassification.differenceColor(entry.amountCents))
            }
            if entry.kind == .expense {
                Picker(L("Zuordnung", "Assignment"), selection: target(of: entry)) {
                    Text(L("Keine", "None")).tag(BookingTarget.none)
                    if !fixedCosts.isEmpty {
                        Section(L("Fixkosten", "Fixed costs")) {
                            ForEach(fixedCosts) { Text($0.name).tag(BookingTarget.fixedCost($0.id)) }
                        }
                    }
                    if !budgets.isEmpty {
                        Section(L("Variable Kosten", "Variable costs")) {
                            ForEach(budgets) { Text($0.name).tag(BookingTarget.variableBudget($0.id)) }
                        }
                    }
                }
                .pickerStyle(.menu)
                if !pools.isEmpty {
                    Picker(L("Pool", "Pool"), selection: pool(of: entry)) {
                        Text(L("Keiner", "None")).tag(UUID?.none)
                        ForEach(pools) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Reads and writes the pool a booking counts for, which is set beside its cost.
    private func pool(of entry: LedgerEntry) -> Binding<UUID?> {
        Binding(
            get: { PoolPayeeRules.poolID(of: entry, context: context) },
            set: { id in
                PoolPayeeRules.setPool(pools.first { $0.id == id }, for: entry, context: context)
                try? context.save()
                revision += 1
            }
        )
    }

    /// Reads and writes the assignment of a booking and saves at once.
    private func target(of entry: LedgerEntry) -> Binding<BookingTarget> {
        Binding(
            get: { BookingTarget(of: entry) },
            set: { target in
                target.apply(to: entry, context: context)
                if case .variableBudget(let id) = target, let budget = budgets.first(where: { $0.id == id }) {
                    VariableBudgetAccounts.include(entry.accountID, in: budget)
                }
                try? context.save()
            }
        )
    }

    private func title(of source: AssignmentInbox.Source) -> String {
        switch source {
        case .bankImport: L("Automatisch zugeordnet beim Import", "Assigned automatically on import")
        case .notice: L("Neu aus Benachrichtigungen", "New from notifications")
        }
    }

    private func footer(of source: AssignmentInbox.Source) -> String {
        switch source {
        case .bankImport:
            L("Diese Buchungen haben über eine IBAN- oder Namensregel Fixkosten, variable Kosten oder einen Pool bekommen.",
              "These bookings got a fixed cost, a variable cost, or a pool through an IBAN or name rule.")
        case .notice:
            L("Seit dem letzten Öffnen per Mitteilung gebucht. Regeln haben sie, wo möglich, schon zugeordnet.",
              "Booked from notifications since the app was last opened. Rules already assigned them where they fit.")
        }
    }
}

/// Opens the assignment check when bookings are waiting.
enum AssignmentReviewTrigger {
    /// The sources that have waiting bookings.
    @MainActor
    static func waitingSources(in entries: [LedgerEntry], among sources: [AssignmentInbox.Source]) -> [AssignmentInbox.Source] {
        sources.filter { !AssignmentInbox.pending($0, in: entries).isEmpty }
    }
}
