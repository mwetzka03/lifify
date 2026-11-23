import LififyCore
import LififyFinance
import SwiftData
import SwiftUI

/// The switch of the return scenario, with the rate of every position.
struct ReturnScenarioSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @AppStorage(ReturnScenario.enabledKey) private var isEnabled = false
    @State private var revision = 0
    @State private var isLoading = false

    var body: some View {
        let _ = revision
        Form {
            Section {
                Toggle(L("Renditeszenario", "Return scenario"), isOn: $isEnabled)
            } footer: {
                Text(L(
                    "ETFs wachsen in künftigen Zeiträumen mit ihrer eigenen Durchschnittsrendite aus 10 Jahren, sonst 5 Jahren, sonst 3 %. Vergangene Renditen sind keine Garantie.",
                    "ETFs grow in future periods at their own average return over 10 years, else 5 years, else 3 %. Past returns are no guarantee."
                ))
            }
            .appGlassRow()
            if isEnabled {
                Section(L("Positionen", "Positions")) {
                    ForEach(holdings) { holdingRow($0) }
                    Button(isLoading ? L("Wird geladen", "Loading") : L("Renditen aktualisieren", "Refresh returns")) {
                        Task { await refresh() }
                    }
                    .disabled(isLoading || holdings.isEmpty)
                }
                .appGlassRow()
            }
        }
        .appGlassList()
        .navigationTitle(L("Renditeszenario", "Return scenario"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: isEnabled) {
            if isEnabled { await refresh() }
        }
    }

    /// One position with its detected type and rate.
    private func holdingRow(_ holding: PortfolioHolding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(holding.name)
                Spacer(minLength: 8)
                Text(rateText(holding))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Picker(L("Art", "Type"), selection: overrideBinding(holding)) {
                ForEach(ETFOverride.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// The rate with its basis, or a note that the position does not grow.
    private func rateText(_ holding: PortfolioHolding) -> String {
        guard ReturnScenario.isETF(holding) else { return L("Kein ETF", "Not an ETF") }
        let rate = ReturnScenario.storedRate(for: holding.symbol)
        let percent = (rate?.annual ?? ReturnScenario.standardAnnual)
            .formatted(.percent.precision(.fractionLength(1)))
        return "\(percent) · \((rate?.basis ?? .standard).label)"
    }

    /// Binds the manual correction of a position.
    private func overrideBinding(_ holding: PortfolioHolding) -> Binding<ETFOverride> {
        Binding(
            get: { ReturnScenario.override(for: holding.symbol) },
            set: {
                ReturnScenario.setOverride($0, for: holding.symbol)
                revision += 1
            }
        )
    }

    /// Loads the current rates.
    private func refresh() async {
        isLoading = true
        await MarketDataService.refreshScenarioRates(holdings: holdings)
        isLoading = false
        revision += 1
    }
}
