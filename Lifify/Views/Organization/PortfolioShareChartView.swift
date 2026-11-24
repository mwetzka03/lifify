import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Whether the chart shows positions or the companies inside the ETFs.
private enum ShareMode: String, CaseIterable, Identifiable {
    case normal
    case deep

    var id: String { rawValue }

    /// The label of the switch.
    var label: String {
        switch self {
        case .normal: L("Normal", "Normal")
        case .deep: L("Tiefenanalyse", "Deep analysis")
        }
    }
}

/// The depot's shares as a chart and list, by position or by company.
struct PortfolioShareChartView: View {
    @EnvironmentObject private var filters: FinanceFilterStore
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \PortfolioHolding.name) private var holdings: [PortfolioHolding]
    @Query private var entries: [LedgerEntry]
    @Query private var forecasts: [IncomeForecast]
    @Query private var accounts: [Account]
    @AppStorage(AppPalette.storageKey) private var paletteRaw = AppPalette.green.rawValue
    @State private var selectedID: String?
    @State private var cache = ShareCache()
    @State private var mode = ShareMode.normal
    @State private var compositionRevision = 0
    @State private var isLoadingFunds = false
    @State private var fundMessage: String?
    @State private var importTarget: PortfolioHolding?
    @State private var showsImporter = false

    private var shareToken: Int {
        var hasher = Hasher()
        hasher.combine(mode)
        hasher.combine(compositionRevision)
        hasher.combine(filters.periodID)
        hasher.combine(filters.accountID)
        hasher.combine(filters.showsDepot)
        hasher.combine(entries.count)
        hasher.combine(forecasts.count)
        hasher.combine(HoldingLotStore.cacheRevision)
        hasher.combine(SavingsPlanStore.cacheRevision)
        hasher.combine(HistoricalPriceStore.cacheRevision)
        hasher.combine(ReturnScenario.revision)
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

    /// Recalculates only when an input changed.
    private var content: ShareContent {
        let token = shareToken
        if cache.token != token {
            cache.token = token
            cache.content = mode == .normal ? ShareContent(shares: makeShares()) : makeDeepContent()
        }
        return cache.content
    }

    private var accent: Color {
        AppLook.accent(AppAppearance(scheme), palette: AppPalette.resolved(paletteRaw)).color()
    }

    var body: some View {
        let content = content
        let displayed = content.pieShares.first { $0.id == selectedID } ?? content.shares.first { $0.id == selectedID }
        List {
            if content.shares.isEmpty {
                ContentUnavailableView(
                    L("Keine Depotpositionen", "No holdings"),
                    systemImage: "chart.pie",
                    description: Text(L("Ohne Bestand gibt es keine Anteile.", "There are no shares without holdings."))
                )
                .appGlassRow()
            } else {
                chartSection(content.pieShares, displayed: displayed)
                modeSection
                listSection(content, displayed: displayed)
                if mode == .deep { fundSection }
            }
        }
        .appGlassList()
        .navigationTitle(L("Anteile", "Shares"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: mode) {
            selectedID = nil
            if mode == .deep { await loadFunds(force: false) }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: Self.importTypes) { result in
            importHoldings(result)
        }
        .alert(L("Zusammensetzung", "Holdings"), isPresented: Binding(
            get: { fundMessage != nil },
            set: { if !$0 { fundMessage = nil } }
        )) {
            Button("OK") { fundMessage = nil }
        } message: {
            Text(fundMessage ?? "")
        }
    }

    /// The file types of a manual holdings import.
    private static var importTypes: [UTType] {
        [.commaSeparatedText, .plainText] + [UTType(filenameExtension: "xlsx")].compactMap { $0 }
    }

    /// The pie with the selected share in its center.
    private func chartSection(_ shares: [PortfolioShare], displayed: PortfolioShare?) -> some View {
        Section {
            ZStack {
                SharePieChart(shares: shares, selectedID: $selectedID)
                    .equatable()
                shareCallout(displayed)
                    .allowsHitTesting(false)
            }
            .frame(height: 280)
            .padding(.vertical, 8)
        }
        .appGlassRow()
    }

    /// The switch between positions and companies.
    private var modeSection: some View {
        Section {
            Picker(L("Ansicht", "View"), selection: $mode) {
                ForEach(ShareMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .appGlassRow()
    }

    /// The list of shares with the notes of the deep analysis.
    private func listSection(_ content: ShareContent, displayed: PortfolioShare?) -> some View {
        Section {
            ForEach(content.shares) { share in
                Button {
                    selectedID = share.id
                } label: {
                    shareRow(share)
                }
                .buttonStyle(.plain)
                .listRowBackground(displayed?.id == share.id ? accent.opacity(0.16) : nil)
            }
        } header: {
            Text(L("Anteile", "Shares"))
        } footer: {
            if !content.notes.isEmpty {
                Text(content.notes.joined(separator: " "))
            }
        }
        .appGlassRow()
    }

    /// One share with its color, value, and percentage.
    private func shareRow(_ share: PortfolioShare) -> some View {
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

    /// The data status of each fund, with refresh and manual import.
    private var fundSection: some View {
        Section {
            ForEach(fundHoldings) { fundRow($0) }
            Button(isLoadingFunds ? L("Wird geladen", "Loading") : L("Zusammensetzungen aktualisieren", "Refresh holdings")) {
                Task { await loadFunds(force: true) }
            }
            .disabled(isLoadingFunds)
        } header: {
            Text(L("ETF-Daten", "ETF data"))
        } footer: {
            Text(L(
                "Index-ETFs nutzen die Gewichte eines Fonds auf denselben Index. Automatisch höchstens einmal pro Woche. Eine eigene CSV- oder Excel-Datei hat Vorrang.",
                "Index ETFs use the weights of a fund on the same index. Automatic at most once a week. Your own CSV or Excel file takes priority."
            ))
        }
        .appGlassRow()
    }

    /// One fund with its data date and import action.
    private func fundRow(_ holding: PortfolioHolding) -> some View {
        let composition = FundCompositionStore.composition(isin: holding.symbol, name: holding.name)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.name)
                Text(fundStatus(composition))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(L("Datei importieren", "Import file"), systemImage: "square.and.arrow.down") {
                    importTarget = holding
                    showsImporter = true
                }
                if composition?.isManual == true {
                    Button(L("Eigene Datei entfernen", "Remove own file"), systemImage: "trash", role: .destructive) {
                        FundCompositionStore.removeManual(isin: holding.symbol)
                        compositionRevision += 1
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .appAccentTint()
        }
    }

    /// Describes where a fund's data comes from.
    private func fundStatus(_ composition: FundComposition?) -> String {
        guard let composition else { return L("Keine Daten, bitte Datei importieren", "No data, please import a file") }
        let source = composition.isManual ? L("Eigene Datei", "Own file") : L("Stand", "As of")
        return "\(source) \(AppDate.numeric(composition.fetchedAt))"
    }

    /// The positions treated as funds.
    private var fundHoldings: [PortfolioHolding] {
        holdings.filter(isFund)
    }

    /// Recognizes a fund by its data source, stored data, market type, or name.
    private func isFund(_ holding: PortfolioHolding) -> Bool {
        let name = holding.name.uppercased()
        return FundSource.resolve(isin: holding.symbol, name: holding.name) != nil
            || FundCompositionStore.composition(isin: holding.symbol, name: holding.name) != nil
            || ReturnScenario.isETF(holding)
            || name.contains("ETF") || name.contains("UCITS")
    }

    /// Loads the funds' holdings and reports failures.
    private func loadFunds(force: Bool) async {
        isLoadingFunds = true
        let funds = fundHoldings.map { (isin: $0.symbol, name: $0.name) }
        let failed = await FundCompositionLoader.refresh(funds: funds, force: force)
        isLoadingFunds = false
        compositionRevision += 1
        if failed > 0, force {
            fundMessage = L("\(failed) Quellen konnten nicht geladen werden.", "\(failed) sources could not be loaded.")
        }
    }

    /// Reads a chosen holdings file for the selected fund.
    private func importHoldings(_ result: Result<URL, Error>) {
        guard let target = importTarget, case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let items = try FundCompositionParser.parse(Data(contentsOf: url), fileExtension: url.pathExtension)
            FundCompositionStore.storeManual(FundComposition(constituents: items, fetchedAt: .now, isManual: true), isin: target.symbol)
            compositionRevision += 1
        } catch {
            fundMessage = L("In dieser Datei wurde keine Bestandsliste gefunden.", "No holdings list was found in this file.")
        }
    }

    /// The selected share in the middle of the chart.
    private func shareCallout(_ share: PortfolioShare?) -> some View {
        VStack(spacing: 4) {
            if let share {
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

    /// The open positions with their value on the shown day, largest first.
    private func valuedHoldings() -> [(PortfolioHolding, Int)] {
        let periods = FinancePeriods.all(entries: entries, forecasts: forecasts, accounts: accounts)
        let projectionDay = filters.period(in: periods)?.end ?? .now
        return holdings.compactMap { holding -> (PortfolioHolding, Int)? in
            let cents = HoldingMaintenance.marketValue(of: holding, through: projectionDay, holdings: holdings)
            let quantity = HoldingMaintenance.quantity(of: holding, through: projectionDay, holdings: holdings)
            guard quantity > 0.0000005, cents > 0 else { return nil }
            return (holding, cents)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
    }

    /// Calculates the shares per position.
    private func makeShares() -> [PortfolioShare] {
        let valued = valuedHoldings()
        let total = valued.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        let nameCounts = Dictionary(grouping: valued, by: { $0.0.name }).mapValues(\.count)
        var seen: [String: Int] = [:]
        return valued.enumerated().map { pair in
            let holding = pair.element.0
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
                id: holding.id.uuidString,
                label: label,
                cents: pair.element.1,
                fraction: Double(pair.element.1) / Double(total),
                colorIndex: pair.offset
            )
        }
    }

    /// Calculates the shares per company with the notes that explain them.
    private func makeDeepContent() -> ShareContent {
        let positions = valuedHoldings().map { holding, cents in
            LookThroughPosition(
                name: holding.name,
                isin: holding.symbol,
                valueCents: cents,
                constituents: FundCompositionStore.composition(isin: holding.symbol, name: holding.name)?.constituents,
                leverage: FundSource.leverage(name: holding.name)
            )
        }
        let funds = Set(fundHoldings.map(\.symbol))
        let result = DepotLookThrough.analyze(positions, otherTitle: L("Sonstige", "Other"), funds: funds)
        let pie = DepotLookThrough.chartLines(result.lines, otherTitle: L("Sonstige", "Other"))
        let pieShares = pie.enumerated().map { index, line in
            PortfolioShare(id: line.id, label: line.label, cents: line.cents, fraction: line.fraction, colorIndex: index)
        }
        let otherColor = pie.count - 1
        let shares = result.lines.map { line in
            let index = pie.firstIndex { !$0.isOther && $0.id == line.id } ?? otherColor
            return PortfolioShare(id: line.id, label: line.label, cents: line.cents, fraction: line.fraction, colorIndex: index)
        }
        return ShareContent(shares: shares, chartShares: pieShares, notes: deepNotes(result))
    }

    /// Explains leverage and funds without data.
    private func deepNotes(_ result: LookThroughResult) -> [String] {
        var notes = [L(
            "In der Liste stehen Einträge unter 0,1 % unter Sonstige, in der Grafik alles unter 0,5 %.",
            "The list combines entries below 0.1 % into Other, the chart everything below 0.5 %."
        )]
        if result.hasLeverage {
            notes.append(L(
                "Hebel-ETFs zählen mit ihrem Hebel, deshalb kann die Summe über 100 % liegen (\(SharePercent.string(result.totalFraction))).",
                "Leveraged ETFs count with their leverage, so the sum can exceed 100 % (\(SharePercent.string(result.totalFraction)))."
            ))
        }
        if !result.uncoveredFunds.isEmpty {
            notes.append(L(
                "Ohne Zusammensetzung als ein Eintrag: \(result.uncoveredFunds.joined(separator: ", ")).",
                "Shown as one entry without holdings: \(result.uncoveredFunds.joined(separator: ", "))."
            ))
        }
        return notes
    }
}

/// The calculated list with its explanations.
private struct ShareContent {
    var shares: [PortfolioShare] = []
    /// The pie's slices when they differ from the list.
    var chartShares: [PortfolioShare]?
    var notes: [String] = []

    /// The slices the pie draws.
    var pieShares: [PortfolioShare] { chartShares ?? shares }
}

/// Keeps the calculated shares between renders.
private final class ShareCache {
    var token: Int?
    var content = ShareContent()
}

/// One position's share.
private struct PortfolioShare: Identifiable, Equatable {
    var id: String
    var label: String
    var cents: Int
    var fraction: Double
    var colorIndex: Int
}

/// The pie itself ignores the selection, so a tap only updates the callout.
private struct SharePieChart: View, @MainActor Equatable {
    let shares: [PortfolioShare]
    @Binding var selectedID: String?

    /// Redraws only when the shares or selection change.
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

    /// Finds the slice at a touch point.
    private func shareID(at location: CGPoint, in size: CGSize) -> String? {
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

/// Formats a share.
private enum SharePercent {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Formats a fraction as a percentage.
    static func string(_ fraction: Double) -> String {
        formatter.locale = Locale(identifier: AppDefaults.store.string(forKey: "appLanguage") == "en" ? "en_US" : "de_DE")
        return formatter.string(from: NSNumber(value: fraction)) ?? "0 %"
    }
}

/// Chart colors from the app's styles, without system blue.
private let palette: [Color] = [
    Color(red: 0.18, green: 0.62, blue: 0.48), Color(red: 0.31, green: 0.49, blue: 0.67),
    Color(red: 0.55, green: 0.18, blue: 0.27), Color(red: 0.48, green: 0.38, blue: 0.66),
    Color(red: 0.85, green: 0.58, blue: 0.25), Color(red: 0.77, green: 0.33, blue: 0.29),
    Color(red: 0.36, green: 0.69, blue: 0.71), Color(red: 0.65, green: 0.72, blue: 0.33),
    Color(red: 0.80, green: 0.47, blue: 0.62), Color(red: 0.55, green: 0.48, blue: 0.40)
]
