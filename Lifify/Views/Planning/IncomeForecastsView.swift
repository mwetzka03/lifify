import SwiftData
import SwiftUI

struct IncomeForecastsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \IncomeForecast.name) private var forecasts: [IncomeForecast]
    @State private var showingNew = false

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
            }
            .onDelete { offsets in
                offsets.map { forecasts[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if forecasts.isEmpty {
                ContentUnavailableView(L("Keine Einnahmeprognosen", "No income forecasts"), systemImage: "calendar.badge.plus")
            }
        }
        .navigationTitle(L("Einnahmeprognosen", "Income forecasts"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { IncomeForecastForm() }
    }
}

private struct IncomeForecastForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.name) private var accounts: [Account]
    @State private var name = ""
    @State private var amount = ""
    @State private var accountID: UUID?
    @State private var cadence = Cadence.monthly
    @State private var firstDate = Date.now
    @State private var dueRule = DueRule.calendarDay
    @State private var day = 1

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
                DatePicker(L("Erste Zahlung", "First payment"), selection: $firstDate, displayedComponents: .date)
                Picker(L("Fälligkeitsregel", "Due rule"), selection: $dueRule) {
                    ForEach(DueRule.allCases) { Text($0.label).tag($0) }
                }
                if dueRule == .calendarDay {
                    Stepper("\(L("Tag", "Day")): \(day)", value: $day, in: 1...31)
                }
            }
            .navigationTitle(L("Neue Prognose", "New forecast"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard let cents = Money.cents(from: amount), !name.isEmpty else { return }
                        context.insert(IncomeForecast(name: name, amountCents: abs(cents), accountID: accountID, cadence: cadence, firstPaymentDate: firstDate, dueRule: dueRule, dayOfMonth: day))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
