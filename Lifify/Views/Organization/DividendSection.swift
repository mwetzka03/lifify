import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// Received dividends and the forecast of the next twelve months.
struct DividendsView: View {
    @Query private var entries: [LedgerEntry]
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @State private var showsYears = false

    var body: some View {
        let report = DividendReportBuilder.make(entries: entries, holdings: holdings)
        List {
            summary(report)
            if !report.forecastMonths.isEmpty { forecastSection(report) }
            if !report.positions.isEmpty { positionSection(report) }
            if !report.months.isEmpty { historySection(report) }
        }
        .overlay {
            if report.positions.isEmpty {
                ContentUnavailableView(
                    L("Keine Dividenden", "No dividends"),
                    systemImage: "banknote",
                    description: Text(L("Erträge aus dem Depot erscheinen hier.", "Income from the depot appears here."))
                )
            }
        }
        .appGlassList()
        .navigationTitle(L("Dividenden", "Dividends"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The received and expected totals.
    @ViewBuilder
    private func summary(_ report: DividendReport) -> some View {
        if !report.positions.isEmpty {
            Section {
                LabeledContent(L("Erhalten", "Received"), value: Money.string(cents: report.totalCents))
                LabeledContent(L("Prognose 12 Monate", "Forecast 12 months"), value: Money.string(cents: report.forecastCents))
            } footer: {
                Text(L(
                    "Die Prognose wiederholt die Zahlungen der letzten 12 Monate je Stück mit dem künftigen Bestand, inklusive Sparplänen.",
                    "The forecast repeats the last 12 months' payments per share with the future holding, including savings plans."
                ))
            }
            .appGlassRow()
        }
    }

    /// The expected payments per month.
    private func forecastSection(_ report: DividendReport) -> some View {
        Section(L("Erwartete Zahlmonate", "Expected months")) {
            ForEach(report.forecastMonths) { month in
                LabeledContent(AppDate.monthYear(month.date), value: Money.string(cents: month.cents))
            }
        }
        .appGlassRow()
    }

    /// The dividends per position.
    private func positionSection(_ report: DividendReport) -> some View {
        Section(L("Je Position", "By position")) {
            ForEach(report.positions) { position in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(position.name)
                        Text("\(L("12 Monate", "12 months")) \(Money.string(cents: position.lastYearCents)) · \(L("Prognose", "Forecast")) \(Money.string(cents: position.forecastCents))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(Money.string(cents: position.totalCents))
                        .foregroundStyle(.green)
                }
            }
        }
        .appGlassRow()
    }

    /// The received dividends per month or year.
    private func historySection(_ report: DividendReport) -> some View {
        Section {
            Picker(L("Ansicht", "View"), selection: $showsYears) {
                Text(L("Monate", "Months")).tag(false)
                Text(L("Jahre", "Years")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ForEach(showsYears ? report.years : report.months) { bucket in
                LabeledContent(showsYears ? bucket.id : AppDate.monthYear(bucket.date), value: Money.string(cents: bucket.cents))
            }
        } header: {
            Text(L("Erhalten", "Received"))
        }
        .appGlassRow()
    }
}
