import LififyCore
import LififyFinance
import SwiftUI

/// Received dividends and the forecast of the next twelve months, folded under the income forecasts.
///
/// It only shows figures. The forecast does not enter the period forecast or any balance.
struct DividendSection: View {
    let entries: [LedgerEntry]
    let holdings: [PortfolioHolding]
    @State private var isOpen = false

    var body: some View {
        let report = DividendReportBuilder.make(entries: entries, holdings: holdings)
        if !report.positions.isEmpty {
            Section {
                header(report)
                if isOpen { details(report) }
            } footer: {
                if isOpen {
                    Text(L(
                        "Die Prognose wiederholt die Zahlungen der letzten 12 Monate je Stück mit dem künftigen Bestand, inklusive Sparplänen. Sie zählt nicht in die Einnahmeprognose. Verkaufte Positionen stehen nur im Erhaltenen.",
                        "The forecast repeats the last 12 months' payments per share with the future holding, including savings plans. It does not count in the income forecast. Sold positions appear only in the received total."
                    ))
                }
            }
            .appGlassRow()
        }
    }

    /// The folding row with the twelve-month forecast.
    private func header(_ report: DividendReport) -> some View {
        Button {
            withAnimation { isOpen.toggle() }
        } label: {
            HStack {
                Label(L("Dividenden", "Dividends"), systemImage: "banknote")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(Money.string(cents: report.forecastCents)) / \(L("12 Mon.", "12 mo."))")
                    .foregroundStyle(.green)
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Received total, expected months, and the paying positions.
    @ViewBuilder
    private func details(_ report: DividendReport) -> some View {
        LabeledContent(L("Bisher erhalten", "Received so far"), value: Money.string(cents: report.totalCents))
        ForEach(report.forecastMonths) { month in
            LabeledContent(AppDate.monthYear(month.date), value: Money.string(cents: month.cents))
                .font(.subheadline)
        }
        ForEach(report.payingPositions) { position in
            HStack(alignment: .firstTextBaseline) {
                Text(position.name).lineLimit(1)
                Spacer(minLength: 12)
                Text(Money.string(cents: position.forecastCents))
                    .foregroundStyle(.green)
            }
            .font(.subheadline)
        }
    }
}
