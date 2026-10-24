import Charts
import SwiftData
import SwiftUI

struct PortfolioShareChartView: View {
    @EnvironmentObject private var filters: FinanceFilterStore
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @State private var selectedID: UUID?
    @State private var cache = ShareCache()

    private var shareToken: Int {
        var hasher = Hasher()
        hasher.combine(filters.periodID)
        hasher.combine(filters.accountID)
        hasher.combine(filters.showsDepot)
        hasher.combine(entries.count)
        hasher.combine(forecasts.count)
        hasher.combine(HoldingLotStore.cacheRevision)
        hasher.combine(SavingsPlanStore.cacheRevision)
        hasher.combine(HistoricalPriceStore.cacheRevision)
        for forecast in forecasts {
            hasher.combine(forecast.id)
            hasher.combine(forecast.amountCents)
            hasher.combine(forecast.isActive)
            hasher.combine(forecast.firstPaymentDate)
        }
        if let earliest = entries.map(\.date).min() {
            hasher.combine(earliest.timeIntervalSinceReferenceDate)
        }
        for holding in holdings {
            hasher.combine(holding.id)
            hasher.combine(holding.name)
            hasher.combine(holding.symbol)
            hasher.combine(holding.quantity)
            hasher.combine(holding.currentPriceCents)
            hasher.combine(holding.purchasePriceCents)
            hasher.combine(holding.updatedAt)
        }
        return hasher.finalize()
    }

    private var shares: [PortfolioShare] {
        let token = shareToken
        if cache.token != token {
            cache.token = token
            cache.shares = makeShares()
        }
        return cache.shares
    }

    private var displayedShare: PortfolioShare? {
        guard let selectedID else { return nil }
        return shares.first { $0.id == selectedID }
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
                        SharePieChart(shares: shares, selectedID: $selectedID)
                            .equatable()
                        shareCallout
                            .allowsHitTesting(false)
                    }
                    .frame(height: 280)
                    .padding(.vertical, 8)
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
                                    Text(SharePercent.string(share.fraction))
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
                Text(SharePercent.string(share.fraction))
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

    private func makeShares() -> [PortfolioShare] {
        let periods = FinancePeriods.all(entries: entries, forecasts: forecasts)
        let projectionDay = filters.period(in: periods)?.end ?? .now
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
}

private final class ShareCache {
    var token: Int?
    var shares: [PortfolioShare] = []
}

private struct PortfolioShare: Identifiable, Equatable {
    var id: UUID
    var label: String
    var cents: Int
    var fraction: Double
    var colorIndex: Int
}

/// The pie itself ignores the selection, so a tap only updates the callout.
private struct SharePieChart: View, Equatable {
    let shares: [PortfolioShare]
    @Binding var selectedID: UUID?

    static func == (lhs: SharePieChart, rhs: SharePieChart) -> Bool {
        lhs.shares == rhs.shares
    }

    var body: some View {
        Chart(shares) { share in
            SectorMark(
                angle: .value("Share", Double(share.cents)),
                innerRadius: .ratio(0.62),
                angularInset: 1.4
            )
            .foregroundStyle(palette[share.colorIndex % palette.count])
        }
        .chartOverlay { _ in
            GeometryReader { geometry in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                selectedID = shareID(at: value.location, in: geometry.size)
                            }
                    )
            }
        }
    }

    private func shareID(at location: CGPoint, in size: CGSize) -> UUID? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        let radius = min(size.width, size.height) / 2
        guard radius > 0, distance <= radius * 0.98, distance >= radius * 0.46 else { return selectedID }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let total = shares.reduce(0.0) { $0 + Double($1.cents) }
        guard total > 0 else { return nil }
        let target = angle / (2 * .pi) * total
        var cursor = 0.0
        for share in shares {
            cursor += Double(share.cents)
            if target <= cursor + 0.001 { return share.id }
        }
        return shares.last?.id
    }
}

private enum SharePercent {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func string(_ fraction: Double) -> String {
        formatter.locale = Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        return formatter.string(from: NSNumber(value: fraction)) ?? "0 %"
    }
}

private let palette: [Color] = [
    .blue, .orange, .green, .pink, .purple, .teal, .indigo, .mint, .cyan, .brown
]
