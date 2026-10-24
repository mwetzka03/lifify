import Charts
import SwiftData
import SwiftUI

struct PortfolioShareChartView: View {
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var selectedID: UUID?
    @State private var selectedAngle: Double?

    private var projectionDay: Date {
        let periods = FinancePeriods.all(entries: entries, forecasts: forecasts)
        return filters.period(in: periods)?.end ?? .now
    }

    private var shares: [PortfolioShare] {
        let valued = holdings.compactMap { holding -> (PortfolioHolding, Int)? in
            let cents = HoldingMaintenance.marketValue(of: holding, through: projectionDay, holdings: holdings)
            let quantity = HoldingMaintenance.quantity(of: holding, through: projectionDay, holdings: holdings)
            guard quantity > 0.0000005, cents > 0 else { return nil }
            return (holding, cents)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
        let total = valued.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        let nameCounts = Dictionary(grouping: valued, by: { $0.0.name }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return valued.enumerated().map { pair in
            let index = pair.offset
            let holding = pair.element.0
            let cents = pair.element.1
            let next = (seen[holding.name] ?? 0) + 1
            seen[holding.name] = next
            let label: String
            if nameCounts[holding.name, default: 1] > 1 {
                let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                label = symbol.isEmpty ? "\(holding.name) \(next)" : "\(holding.name) \(next) · \(symbol)"
            } else {
                label = holding.name
            }
            return PortfolioShare(
                id: holding.id,
                label: label,
                cents: cents,
                fraction: Double(cents) / Double(total),
                colorIndex: index
            )
        }
    }

    private var displayedShare: PortfolioShare? {
        if let selectedID, let match = shares.first(where: { $0.id == selectedID }) {
            return match
        }
        return share(at: selectedAngle)
    }

    var body: some View {
        List {
            if shares.isEmpty {
                ContentUnavailableView(
                    L("Keine Depotpositionen", "No holdings"),
                    systemImage: "chart.pie",
                    description: Text(L("Ohne Bestand gibt es keine Anteile.", "There are no shares without holdings."))
                )
            } else {
                Section {
                    ZStack {
                        Chart(shares) { share in
                            SectorMark(
                                angle: .value(L("Anteil", "Share"), Double(share.cents)),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.4
                            )
                            .foregroundStyle(palette[share.colorIndex % palette.count])
                            .opacity(sliceOpacity(share))
                        }
                        .chartAngleSelection(value: $selectedAngle)
                        shareCallout
                            .allowsHitTesting(false)
                    }
                    .frame(height: 280)
                    .padding(.vertical, 8)
                    .onChange(of: selectedAngle) { _, angle in
                        if let match = share(at: angle) {
                            selectedID = match.id
                        }
                    }
                }
                Section(L("Anteile", "Shares")) {
                    ForEach(shares) { share in
                        Button {
                            selectedID = share.id
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(palette[share.colorIndex % palette.count])
                                    .frame(width: 12, height: 12)
                                Text(share.label)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Money.string(cents: share.cents))
                                        .foregroundStyle(.primary)
                                    Text(percentText(share.fraction))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(displayedShare?.id == share.id ? Color.accentColor.opacity(0.12) : nil)
                    }
                }
            }
        }
        .navigationTitle(L("Anteile", "Shares"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shareCallout: some View {
        VStack(spacing: 4) {
            if let share = displayedShare {
                Text(share.label)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(Money.string(cents: share.cents))
                    .font(.title3.bold())
                Text(percentText(share.fraction))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("Anteil antippen", "Tap a share"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 64)
        .frame(maxWidth: .infinity)
    }

    private func sliceOpacity(_ share: PortfolioShare) -> Double {
        guard let displayedShare else { return 1 }
        return displayedShare.id == share.id ? 1 : 0.38
    }

    /// Maps a chart angle back onto a slice. Charts may report the cumulative euro value, radians, or degrees.
    private func share(at angle: Double?) -> PortfolioShare? {
        guard let angle, angle >= 0, !shares.isEmpty else { return nil }
        let total = shares.reduce(0.0) { $0 + Double($1.cents) }
        guard total > 0 else { return nil }
        let position: Double
        if angle <= total + 0.5 {
            position = angle
        } else if angle <= (.pi * 2) + 0.05 {
            position = angle / (2 * .pi) * total
        } else if angle <= 360 {
            position = angle / 360 * total
        } else {
            position = angle.truncatingRemainder(dividingBy: total)
        }
        var cursor = 0.0
        for share in shares {
            cursor += Double(share.cents)
            if position <= cursor + 0.001 { return share }
        }
        return shares.last
    }

    private func percentText(_ fraction: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        return formatter.string(from: NSNumber(value: fraction)) ?? "0 %"
    }
}

private struct PortfolioShare: Identifiable {
    var id: UUID
    var label: String
    var cents: Int
    var fraction: Double
    var colorIndex: Int
}

private let palette: [Color] = [
    .blue, .orange, .green, .pink, .purple, .teal, .indigo, .mint, .cyan, .brown
]
