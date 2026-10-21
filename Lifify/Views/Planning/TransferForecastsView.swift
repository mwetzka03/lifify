import SwiftData
import SwiftUI

struct TransferForecastsView: View {
    @State private var forecasts: [TransferForecastRecord] = []
    @State private var showingNew = false
    @State private var edited: TransferForecastRecord?

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
                }
                .contentShape(Rectangle())
                .onTapGesture { edited = forecast }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        TransferForecastStore.remove(id: forecast.id)
                        reload()
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
                ContentUnavailableView(L("Keine Umbuchungsprognosen", "No transfer forecasts"), systemImage: "arrow.left.arrow.right")
            }
        }
        .navigationTitle(L("Umbuchungsprognosen", "Transfer forecasts"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .onAppear { reload() }
        .sheet(isPresented: $showingNew, onDismiss: { reload() }) { TransferForecastForm(forecast: nil) }
        .sheet(item: $edited, onDismiss: { reload() }) { TransferForecastForm(forecast: $0) }
    }

    private func reload() {
        forecasts = TransferForecastStore.all().sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

struct TransferForecastForm: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.name) private var accounts: [Account]
    private let existing: TransferForecastRecord?
    @State private var name: String
    @State private var amount: String
    @State private var fromAccountID: UUID?
    @State private var toAccountID: UUID?
    @State private var cadence: Cadence
    @State private var firstDate: Date
    @State private var dueRule: DueRule
    @State private var day: Int

    init(forecast: TransferForecastRecord?) {
        existing = forecast
        _name = State(initialValue: forecast?.name ?? "")
        _amount = State(initialValue: forecast.map { String(format: "%.2f", Double(abs($0.amountCents)) / 100) } ?? "")
        _fromAccountID = State(initialValue: forecast?.fromAccountID)
        _toAccountID = State(initialValue: forecast?.toAccountID)
        _cadence = State(initialValue: forecast?.cadence ?? .monthly)
        _firstDate = State(initialValue: forecast?.firstDate ?? .now)
        _dueRule = State(initialValue: forecast?.dueRule ?? .calendarDay)
        _day = State(initialValue: forecast?.dayOfMonth ?? 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Name", "Name"), text: $name)
                TextField(L("Betrag", "Amount"), text: $amount).keyboardType(.decimalPad)
                Picker(L("Von", "From"), selection: $fromAccountID) {
                    Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                    ForEach(cashAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker(L("Nach", "To"), selection: $toAccountID) {
                    Text(L("Auswählen", "Select")).tag(Optional<UUID>.none)
                    ForEach(cashAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }
                Picker(L("Rhythmus", "Cadence"), selection: $cadence) {
                    ForEach(Cadence.allCases) { Text($0.label).tag($0) }
                }
                AppDateField(title: L("Erste Umbuchung", "First transfer"), selection: $firstDate)
                Picker(L("Fälligkeitsregel", "Due rule"), selection: $dueRule) {
                    ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                }
                if dueRule == .calendarDay {
                    Stepper("\(L("Tag", "Day")): \(day)", value: $day, in: 1...31)
                }
            }
            .navigationTitle(existing == nil ? L("Neue Prognose", "New forecast") : L("Prognose bearbeiten", "Edit forecast"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) { save() }
                }
            }
        }
    }

    private var cashAccounts: [Account] {
        accounts.filter { $0.kind != .portfolio && $0.kind != .savingsGroup }
    }

    private func save() {
        guard let cents = Money.cents(from: amount), cents != 0, !name.isEmpty else { return }
        guard let fromAccountID, let toAccountID, fromAccountID != toAccountID else { return }
        var forecast = existing ?? TransferForecastRecord(name: name, amountCents: abs(cents))
        forecast.name = name
        forecast.amountCents = abs(cents)
        forecast.fromAccountID = fromAccountID
        forecast.toAccountID = toAccountID
        forecast.cadence = cadence
        forecast.firstDate = firstDate
        forecast.dueRule = dueRule
        forecast.dayOfMonth = day
        forecast.active = true
        TransferForecastStore.upsert(forecast)
        dismiss()
    }
}
