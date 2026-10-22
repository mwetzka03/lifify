import SwiftData
import SwiftUI

struct FixedCostDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var splits: [TransactionSplit]
    let cost: FixedCost
    @State private var selected: LedgerEntry?
    @State private var editing: LedgerEntry?
    @State private var showingEdit = false
    @AppStorage(ForecastPeriodLinkStore.revisionKey) private var forecastLinkRevision = 0
    @AppStorage(ForecastMatchRejectionStore.revisionKey) private var forecastRejectionRevision = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(L("Rhythmus", "Cadence"), value: cost.cadence.label)
                    LabeledContent(L("Betrag", "Amount"), value: Money.string(cents: abs(cost.amountCents)))
                    if !cost.isActive {
                        Text(L("Beendet", "Ended"))
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if assigned.isEmpty {
                        Text(L("Noch keine Buchung zugeordnet.", "No transaction is assigned yet."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(assigned) { entry in
                        Button {
                            selected = entry
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .foregroundStyle(.primary)
                                    Text(AppDate.numeric(entry.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.string(cents: -abs(entry.amountCents)))
                                    .foregroundStyle(.red)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                unlink(entry)
                            } label: {
                                Label(L("Entfernen", "Remove"), systemImage: "minus.circle")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editing = entry
                            } label: {
                                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text(L("Zugewiesene Buchungen", "Assigned transactions"))
                } footer: {
                    Text(L(
                        "Entfernen löst nur die Zuweisung. Die Buchung bleibt bestehen.",
                        "Remove clears only the assignment. The transaction stays."
                    ))
                }
                Section {
                    if upcoming.isEmpty {
                        Text(L("Keine weitere Abbuchung.", "No further debit."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { charge in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(charge.title)
                                Text(charge.isPaid ? L("Gebucht", "Booked") : L("Prognose", "Forecast"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.string(cents: -charge.amount))
                                    .foregroundStyle(charge.isPaid ? Color.secondary : Color.red)
                                Text(AppDate.numeric(charge.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .opacity(charge.isPaid ? 0.45 : 1)
                    }
                } header: {
                    Text(L("Nächste Prognosen", "Next forecasts"))
                }
            }
            .navigationTitle(cost.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(L("Bearbeiten", "Edit"))
                }
            }
        }
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
        .sheet(item: $editing) { TransactionFormView(entry: $0, splits: splits) }
        .sheet(isPresented: $showingEdit) { FixedCostForm(cost: cost) }
    }

    private var assigned: [LedgerEntry] {
        _ = forecastLinkRevision
        _ = forecastRejectionRevision
        return FinanceService.assignedBookings(for: cost, entries: entries).filter(matchesAccount)
    }

    private var upcoming: [ScheduledCharge] {
        _ = forecastLinkRevision
        _ = forecastRejectionRevision
        return FinanceService.upcomingCharges(for: cost, entries: entries, limit: 3)
    }

    private var selectedAccount: Account? {
        let account = filters.account(in: accounts.filter { $0.kind != .savingsGroup })
        return account?.kind == .portfolio ? nil : account
    }

    private func matchesAccount(_ entry: LedgerEntry) -> Bool {
        guard let account = selectedAccount else { return true }
        return entry.accountID == account.id || entry.fromAccountID == account.id || entry.toAccountID == account.id
    }

    private func unlink(_ entry: LedgerEntry) {
        if let link = ForecastPeriodLinkStore.link(for: entry.id), link.kind == .fixed, link.id == cost.id {
            ForecastPeriodLinkStore.clear(entryID: entry.id)
        }
        if entry.fixedCostID == cost.id {
            entry.fixedCostID = nil
            try? context.save()
        }
        ForecastMatchRejectionStore.reject(costID: cost.id, entryID: entry.id)
    }
}
