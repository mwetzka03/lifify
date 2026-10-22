import SwiftData
import SwiftUI

struct IncomeOverviewView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeForecast.name) private var forecasts: [IncomeForecast]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @State private var showingNew = false
    @State private var edited: IncomeForecast?
    @State private var selected: LedgerEntry?

    private var incomeEntries: [LedgerEntry] {
        entries.filter { $0.kind == .income && !BookingClassification.isRefund($0) }
    }

    var body: some View {
        List {
            Section {
                if forecasts.isEmpty {
                    Text(L("Noch keine Einnahmeprognosen.", "No income forecasts yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(forecasts) { forecast in
                    forecastRow(forecast)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                context.delete(forecast)
                                try? context.save()
                            } label: {
                                Label(L("Löschen", "Delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { edited = forecast } label: {
                                Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
                Button {
                    showingNew = true
                } label: {
                    Label(L("Prognose hinzufügen", "Add forecast"), systemImage: "plus")
                }
            } header: {
                Text(L("Einnahmeprognosen", "Income forecasts"))
            }
            Section(L("Buchungen", "Transactions")) {
                if incomeEntries.isEmpty {
                    Text(L("Noch keine Einnahmen.", "No income yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(incomeEntries) { entry in
                    Button { selected = entry } label: { TransactionRow(entry: entry, ledgerEntries: entries) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(L("Einnahmen", "Income"))
        .sheet(isPresented: $showingNew) { IncomeForecastForm(forecast: nil) }
        .sheet(item: $edited) { IncomeForecastForm(forecast: $0) }
        .sheet(item: $selected) { TransactionDetailView(entry: $0) }
    }

    private func forecastRow(_ forecast: IncomeForecast) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(forecast.name)
                Text("\(forecast.cadence.label) · \(forecast.dueRule.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.string(cents: abs(forecast.amountCents)))
                .foregroundStyle(.green)
        }
    }
}

struct IncomeForecastsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeForecast.name) private var forecasts: [IncomeForecast]
    @State private var showingNew = false
    @State private var edited: IncomeForecast?

    var body: some View {
        List {
            ForEach(forecasts) { forecast in
                HStack {
                    VStack(alignment: .leading) {
                        Text(forecast.name)
                        Text("\(forecast.cadence.label) · \(forecast.dueRule.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.string(cents: abs(forecast.amountCents)))
                        .foregroundStyle(.green)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        context.delete(forecast)
                        try? context.save()
                    } label: {
                        Label(L("Löschen", "Delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button { edited = forecast } label: {
                        Label(L("Bearbeiten", "Edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .overlay {
            if forecasts.isEmpty {
                ContentUnavailableView(L("Keine Einnahmeprognosen", "No income forecasts"), systemImage: "calendar.badge.plus")
            }
        }
        .navigationTitle(L("Einnahmeprognosen", "Income forecasts"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { IncomeForecastForm(forecast: nil) }
        .sheet(item: $edited) { IncomeForecastForm(forecast: $0) }
    }
}

struct IncomeForecastForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    private let existing: IncomeForecast?
    @State private var name: String
    @State private var amount: String
    @State private var accountID: UUID?
    @State private var cadence: Cadence
    @State private var firstDate: Date
    @State private var dueRule: DueRule
    @State private var day: Int

    init(forecast: IncomeForecast?) {
        existing = forecast
        _name = State(initialValue: forecast?.name ?? "")
        _amount = State(initialValue: forecast.map { String(format: "%.2f", Double($0.amountCents) / 100) } ?? "")
        _accountID = State(initialValue: forecast?.accountID)
        _cadence = State(initialValue: forecast?.cadence ?? .monthly)
        _firstDate = State(initialValue: forecast?.firstPaymentDate ?? .now)
        _dueRule = State(initialValue: forecast?.dueRule ?? .calendarDay)
        _day = State(initialValue: forecast?.dayOfMonth ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Betrag", "Amount"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Konto", "Account"), selection: $accountID) {
                    Text(L("Keins", "None")).tag(Optional<UUID>.none)
                    ForEach(accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                Picker(L("Rhythmus", "Cadence"), selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.label).tag($0) }
                }
                AppDateField(title: L("Erste Zahlung", "First payment"), selection: $firstDate)
                Picker(L("Fälligkeitsregel", "Due rule"), selection: $dueRule) {
                    ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                }
                if dueRule == .calendarDay {
                    Stepper("\(L("Tag", "Day")): \(day)", value: $day, in: 1...31)
                }
            }
            .navigationTitle(existing == nil ? L("Neue Einnahmenprognose", "New income forecast") : L("Einnahmenprognose bearbeiten", "Edit income forecast"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private func save() {
        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
        let forecast = existing ?? IncomeForecast(name: name, amountCents: abs(cents))
        forecast.name = name
        forecast.amountCents = abs(cents)
        forecast.accountID = accountID
        forecast.cadence = cadence
        forecast.firstPaymentDate = firstDate
        forecast.dueRule = dueRule
        forecast.dayOfMonth = day
        if existing == nil { context.insert(forecast) }
        try? context.save()
        dismiss()
    }
}
