import Foundation

struct TradeRepublicActivity: Equatable, Sendable {
    var id: String
    var date: Date
    var title: String
    var eventType: String
    var amountCents: Int
    var isin: String
    var trade: Bool
    var status: String
    /// Same label the PDF statement uses: Ertrag, Zinsen, Kartentransaktion, Überweisung, Steuern, Bonus, Empfehlung.
    var statementType: String = ""
    /// Share count from the timeline row or its detail. Missing means the row must not invent one.
    var quantity: Double? = nil
    var savingsPlan: Bool = false

    var isGrant: Bool { statementType == "Cashback" || statementType == "Depotgeschenk" }
}

struct TradeRepublicPlan: Equatable, Sendable {
    var isin: String
    var name: String
    var amountCents: Int
    var interval: String
    var active: Bool
}

struct TradeRepublicSnapshot: Equatable, Sendable {
    var positions: [TradeRepublicPosition]
    var activities: [TradeRepublicActivity]
    var plans: [TradeRepublicPlan] = []
}

struct HeldPosition: Equatable {
    var symbol: String
    var name: String
    var quantity: Double
    var purchasePriceCents: Int
    var latestLotDate: Date?
}

enum TradeRepublicMove: Equatable {
    case cash(id: String, date: Date, title: String, amountCents: Int, statementType: String)
    case grant(id: String, date: Date, title: String, isin: String, name: String, quantity: Double, amountCents: Int, statementType: String)
    case shares(id: String, date: Date, isin: String, name: String, quantity: Double, unitCents: Int)
    case buy(id: String, date: Date, title: String, isin: String, name: String, quantity: Double, amountCents: Int, savingsPlan: Bool)
    case sale(id: String, date: Date, title: String, isin: String, name: String, quantity: Double, amountCents: Int)
    case drop(isin: String)
}

enum TradeRepublicTimeline {
    static func read(text: String) -> (items: [TradeRepublicActivity], after: String?) {
        guard let start = text.firstIndex(of: "{") else { return ([], nil) }
        return read(Data(text[start...].utf8))
    }

    static func read(_ data: Data) -> (items: [TradeRepublicActivity], after: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([], nil) }
        let rows = object["items"] as? [[String: Any]] ?? []
        let cursors = object["cursors"] as? [String: Any]
        let after = (cursors?["after"] as? String) ?? (object["after"] as? String)
        return (rows.compactMap(activity), after)
    }

    static let openingBalanceFingerprint = "tr-startsaldo"

    static func fingerprint(_ id: String) -> String { "tr-\(id)" }

    private static func activity(_ row: [String: Any]) -> TradeRepublicActivity? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        let status = (row["status"] as? String) ?? ""
        guard isFinished(status) else { return nil }
        guard let date = date(from: (row["timestamp"] as? String) ?? "") else { return nil }
        let amount = cents(row["amount"] as? [String: Any]) ?? 0
        let eventType = (row["eventType"] as? String) ?? ""
        let isin = isin(from: (row["icon"] as? String) ?? "")
        let title = ((row["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (row["subtitle"] as? String) ?? ""
        let trade = amount != 0 && isTrade(eventType, isin: isin)
        let kind = statementType(eventType: eventType, title: title, subtitle: subtitle, isin: isin, amountCents: amount, trade: trade)
        guard amount != 0 || kind == "Cashback" || kind == "Depotgeschenk" || kind == "IPO" || mightBeGrant(eventType) || title.count >= 4 else { return nil }
        var item = TradeRepublicActivity(
            id: id,
            date: date,
            title: title,
            eventType: eventType,
            amountCents: amount,
            isin: isin,
            trade: trade,
            status: status,
            quantity: shareCount(row),
            savingsPlan: isSavingsPlan(eventType)
        )
        item.statementType = kind
        return item
    }

    static func enrich(_ item: TradeRepublicActivity, detail text: String) -> TradeRepublicActivity {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8))
        else { return item }
        var copy = item
        if let symbol = labeledText(in: object, titles: ["isin"]), !symbol.isEmpty, copy.isin.isEmpty {
            copy.isin = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        copy.trade = copy.amountCents != 0 && isTrade(copy.eventType, isin: copy.isin)
        copy.statementType = statementType(
            eventType: copy.eventType,
            title: copy.title,
            subtitle: "",
            isin: copy.isin,
            amountCents: copy.amountCents,
            trade: copy.trade
        )
        if (copy.trade || copy.isGrant), let shares = transactionShares(in: object) {
            copy.quantity = shares
        }
        if let savings = orderTypeIsSavings(in: object) {
            copy.savingsPlan = savings
        }
        return copy
    }

    /// One compact line per timeline row, including amount-0 gifts the booking parser might skip.
    static func indexLines(from text: String) -> [String] {
        guard let start = text.firstIndex(of: "{") else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8)) as? [String: Any] else {
            return []
        }
        let rows = object["items"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            let id = (row["id"] as? String) ?? ""
            guard !id.isEmpty else { return nil }
            let title = ((row["title"] as? String) ?? "")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let amount = cents(row["amount"] as? [String: Any]) ?? 0
            return [
                (row["timestamp"] as? String) ?? "",
                (row["eventType"] as? String) ?? "",
                (row["status"] as? String) ?? "",
                "\(amount)",
                isin(from: (row["icon"] as? String) ?? ""),
                title,
                id
            ].joined(separator: "\t")
        }
    }

    static func activities(fromIndex text: String) -> [TradeRepublicActivity] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            activity(fromIndexLine: String(line))
        }
    }

    static func mightBeGrant(_ eventType: String) -> Bool {
        let folded = eventType.uppercased().replacingOccurrences(of: "_", with: "")
        return folded.contains("GIFT")
            || folded.contains("GESCHENK")
            || folded.contains("PERK")
            || folded.contains("WELCOME")
            || folded.contains("ACQUISITION")
            || folded.contains("SECURITIESTRANSFER")
            || folded.contains("STOCKTRANSFER")
            || folded.contains("SHARETRANSFER")
            || folded.contains("INCOMINGTRANSFER")
            || folded.contains("UBERTRAG")
            || folded.contains("BENEFIT")
    }

    private static func activity(fromIndexLine line: String) -> TradeRepublicActivity? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 7 else { return nil }
        let status = parts[2]
        guard isFinished(status) else { return nil }
        guard let date = date(from: parts[0]) else { return nil }
        let eventType = parts[1]
        let amount = Int(parts[3]) ?? 0
        let isin = parts[4]
        let title = parts[5]
        let id = parts[6]
        guard !id.isEmpty else { return nil }
        let trade = amount != 0 && isTrade(eventType, isin: isin)
        let kind = statementType(eventType: eventType, title: title, subtitle: "", isin: isin, amountCents: amount, trade: trade)
        guard amount != 0 || kind == "Cashback" || kind == "Depotgeschenk" || kind == "IPO" || mightBeGrant(eventType) || title.count >= 4 else { return nil }
        var item = TradeRepublicActivity(
            id: id,
            date: date,
            title: title,
            eventType: eventType,
            amountCents: amount,
            isin: isin,
            trade: trade,
            status: status.isEmpty ? "EXECUTED" : status,
            savingsPlan: isSavingsPlan(eventType)
        )
        item.statementType = kind
        return item
    }

    private static func statementType(
        eventType: String,
        title: String,
        subtitle: String,
        isin: String,
        amountCents: Int,
        trade: Bool
    ) -> String {
        let compact = "\(eventType) \(title) \(subtitle)"
            .uppercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "_", with: "")
        if compact.contains("SAVEBACK") || compact.contains("CASHBACK") { return "Cashback" }
        if compact.contains("PERK"), amountCents != 0 { return "Cashback" }
        if compact.contains("IPO") { return "IPO" }
        if isGift(compact, isin: isin) { return "Depotgeschenk" }
        if amountCents == 0, !isin.isEmpty, !isCorporateAction(compact) { return "Depotgeschenk" }
        if trade { return "Handel" }
        if compact.contains("DIVIDEND") || compact.contains("DIVIDENDE") { return "Ertrag" }
        if compact.contains("INTEREST") || compact.contains("ZINS") { return "Zinsen" }
        if compact.contains("TAX") || compact.contains("STEUER") { return "Steuern" }
        if compact.contains("CARD") { return "Kartentransaktion" }
        if compact.contains("BONUS") { return "Bonus" }
        if compact.contains("REFERRAL") || compact.contains("EMPFEHLUNG") { return "Empfehlung" }
        if compact.contains("BANK") || compact.contains("TRANSFER") || compact.contains("UBERWEISUNG") { return "Überweisung" }
        if !isin.isEmpty && amountCents > 0 { return "Ertrag" }
        return ""
    }

    private static func isGift(_ compact: String, isin: String) -> Bool {
        if compact.contains("GIFT") || compact.contains("GESCHENK") || compact.contains("PERK") || compact.contains("WELCOME") {
            return true
        }
        guard !isin.isEmpty else { return false }
        return compact.contains("SECURITIESTRANSFER")
            || compact.contains("STOCKTRANSFER")
            || compact.contains("SHARETRANSFER")
            || compact.contains("INCOMINGTRANSFER")
            || compact.contains("UBERTRAG")
    }

    private static func isCorporateAction(_ compact: String) -> Bool {
        compact.contains("SPLIT") || compact.contains("MERGER") || compact.contains("SPINOFF") || compact.contains("SPIN-OFF")
    }

    private static func isFinished(_ status: String) -> Bool {
        let folded = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return folded.isEmpty
            || folded == "EXECUTED"
            || folded == "PROCESSED"
            || folded == "COMPLETED"
    }

    private static func isSavingsPlan(_ eventType: String) -> Bool {
        let folded = eventType.uppercased().replacingOccurrences(of: "_", with: "")
        return folded.contains("SAVINGSPLAN") || folded.contains("SAVINGPLAN")
    }

    private static func isTrade(_ eventType: String, isin: String) -> Bool {
        guard !isin.isEmpty else { return false }
        let folded = eventType.uppercased().replacingOccurrences(of: "_", with: "")
        if folded.contains("DIVIDEND") || folded.contains("INTEREST") || folded.contains("ZINS") || folded.contains("IPO")
            || folded.contains("SAVEBACK") || folded.contains("CASHBACK")
            || folded.contains("GIFT") || folded.contains("GESCHENK") || folded.contains("PERK") {
            return false
        }
        return folded.contains("TRADINGTRADE") || folded.contains("TRADINGSAVING") || folded.contains("ORDEREXECUTED")
    }

    private static func isin(from icon: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"logos/([A-Z]{2}[A-Z0-9]{9}[0-9])"#),
              let match = regex.firstMatch(in: icon, range: NSRange(icon.startIndex..., in: icon)),
              let range = Range(match.range(at: 1), in: icon)
        else { return "" }
        return String(icon[range])
    }

    private static func cents(_ amount: [String: Any]?) -> Int? {
        guard let amount, let number = doubleValue(amount["value"]) else { return nil }
        let digits = intValue(amount["fractionDigits"]) ?? 2
        return Int((number * pow(10, Double(digits))).rounded())
    }

    private static func date(from text: String) -> Date? {
        let normalized = text.replacingOccurrences(of: "+0000", with: "Z")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text.replacingOccurrences(of: ",", with: "."))
        default: return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int: return number
        case let number as NSNumber: return number.intValue
        default: return nil
        }
    }

    private static func shareCount(_ row: [String: Any]) -> Double? {
        if let number = doubleValue(row["shares"] ?? row["quantity"] ?? row["netSize"] ?? row["size"]), number > 0 {
            return number
        }
        let subtitle = (row["subtitle"] as? String) ?? ""
        return number(in: subtitle, unit: true)
    }

    /// "0,025303 × 197,60 €" and the Aktien row. Aktienkurs is the price, not the share count.
    private static func transactionShares(in object: Any) -> Double? {
        if let row = object as? [String: Any] {
            let title = ((row["title"] as? String) ?? "")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if title == "transaktion" || title == "transaction", let detail = row["detail"] as? [String: Any] {
                if let display = detail["displayValue"] as? [String: Any],
                   let prefix = display["prefix"] as? String,
                   let shares = number(in: prefix, unit: false) {
                    return shares
                }
                if let text = detail["text"] as? String, text.contains("×") || text.contains(" x "),
                   let shares = number(in: text, unit: false) {
                    return shares
                }
            }
            if ["aktien", "shares", "anteile", "stuck", "stueck"].contains(title),
               !title.contains("kurs"),
               let detail = row["detail"] as? [String: Any],
               let text = detail["text"] as? String,
               let shares = number(in: text, unit: false) {
                return shares
            }
            for value in row.values {
                if let found = transactionShares(in: value) { return found }
            }
        } else if let list = object as? [Any] {
            for value in list {
                if let found = transactionShares(in: value) { return found }
            }
        }
        return nil
    }

    private static func labeledText(in object: Any, titles: [String]) -> String? {
        if let row = object as? [String: Any] {
            let title = ((row["title"] as? String) ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            if titles.contains(where: { title.contains($0) }) {
                if let text = row["detail"] as? [String: Any], let value = text["text"] as? String, !value.isEmpty {
                    return value
                }
                if let value = row["detail"] as? String, !value.isEmpty { return value }
            }
            for value in row.values {
                if let found = labeledText(in: value, titles: titles) { return found }
            }
        } else if let list = object as? [Any] {
            for value in list {
                if let found = labeledText(in: value, titles: titles) { return found }
            }
        }
        return nil
    }

    /// Only the order-type row decides. A section that merely links a savings plan does not.
    private static func orderTypeIsSavings(in object: Any) -> Bool? {
        guard let text = exactLabeledText(in: object, titles: ["orderart", "ordertype", "order type", "art"]) else { return nil }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        return folded == "sparplan" || folded == "savings plan" || folded == "savingsplan"
    }

    private static func exactLabeledText(in object: Any, titles: [String]) -> String? {
        if let row = object as? [String: Any] {
            let title = ((row["title"] as? String) ?? "")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if titles.contains(title) {
                if let text = row["detail"] as? [String: Any], let value = text["text"] as? String, !value.isEmpty {
                    return value
                }
                if let value = row["detail"] as? String, !value.isEmpty { return value }
            }
            for value in row.values {
                if let found = exactLabeledText(in: value, titles: titles) { return found }
            }
        } else if let list = object as? [Any] {
            for value in list {
                if let found = exactLabeledText(in: value, titles: titles) { return found }
            }
        }
        return nil
    }

    private static func number(in text: String, unit: Bool) -> Double? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if unit && !folded.contains("stk") && !folded.contains("stuck") && !folded.contains("share") && !folded.contains("anteil") {
            return nil
        }
        guard let expression = try? NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)"#),
              let match = expression.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let range = Range(match.range(at: 1), in: folded)
        else { return nil }
        return Double(folded[range].replacingOccurrences(of: ",", with: "."))
    }
}

enum TradeRepublicSync {
    /// A buy whose price is a few cents per share is a dividend, not a purchase.
    static func purchase(_ item: TradeRepublicActivity, averageCents: Int) -> Bool {
        guard item.trade, item.amountCents < 0, let quantity = item.quantity, quantity > 0.0000005 else { return false }
        guard averageCents > 0 else { return true }
        let unit = Int((Double(abs(item.amountCents)) / quantity).rounded())
        return unit >= max(averageCents / 8, 1) && unit <= averageCents * 8
    }

    static func changes(
        positions: [TradeRepublicPosition],
        holdings: [HeldPosition],
        activities: [TradeRepublicActivity],
        known: Set<String>,
        now: Date = .now
    ) -> [TradeRepublicMove] {
        let fresh = activities.filter { !known.contains(TradeRepublicTimeline.fingerprint($0.id)) }
        let live = Dictionary(grouping: positions.filter { $0.quantity > 0.0000005 }, by: { $0.isin.uppercased() })
            .compactMapValues(\.first)
        let leaving = holdings.filter { holding in
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return !symbol.isEmpty && live[symbol] == nil && holding.quantity > 0.0000005
        }
        var moves: [TradeRepublicMove] = []
        for item in fresh where !item.trade {
            if item.isGrant {
                if (item.quantity ?? 0) > 0.0000005 { continue }
                if item.statementType == "Depotgeschenk" { continue }
                let value = abs(item.amountCents)
                guard value > 0 else { continue }
                moves.append(.grant(
                    id: item.id,
                    date: item.date,
                    title: item.title.isEmpty ? "Trade Republic" : item.title,
                    isin: item.isin,
                    name: item.title,
                    quantity: 0,
                    amountCents: value,
                    statementType: item.statementType
                ))
                continue
            }
            if item.amountCents > 0 && leaving.contains(where: { claimsSale($0, item: item) }) { continue }
            let title = item.title.isEmpty ? "Trade Republic" : item.title
            moves.append(.cash(id: item.id, date: item.date, title: title, amountCents: item.amountCents, statementType: item.statementType))
        }
        let giftDates = giftDates(positions: Array(live.values), activities: activities)
        var seen = Set<String>()
        for holding in holdings {
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbol.isEmpty else { continue }
            seen.insert(symbol)
            guard let position = live[symbol] else {
                appendExit(holding, symbol: symbol, activities: activities, known: known, now: now, into: &moves)
                continue
            }
            let added = appendBuys(
                position: position,
                holding: holding,
                activities: fresh,
                history: activities,
                giftDates: giftDates,
                now: now,
                into: &moves
            )
            let have = holding.quantity + added
            if have - position.quantity > 0.001 {
                appendSales(
                    quantity: have - position.quantity,
                    position: position,
                    holding: holding,
                    activities: fresh,
                    now: now,
                    into: &moves
                )
            }
        }
        for (symbol, position) in live where !seen.contains(symbol) {
            seen.insert(symbol)
            let added = appendBuys(
                position: position,
                holding: nil,
                activities: fresh,
                history: activities,
                giftDates: giftDates,
                now: now,
                into: &moves
            )
            if added - position.quantity > 0.001 {
                appendSales(
                    quantity: added - position.quantity,
                    position: position,
                    holding: HeldPosition(
                        symbol: symbol,
                        name: position.name,
                        quantity: added,
                        purchasePriceCents: position.averageBuyInCents ?? 0,
                        latestLotDate: nil
                    ),
                    activities: fresh,
                    now: now,
                    into: &moves
                )
            }
        }
        let extra = Set(
            fresh.compactMap { item -> String? in
                let symbol = item.isin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard item.trade, !symbol.isEmpty, seen.contains(symbol) == false else { return nil }
                return symbol
            }
        )
        for symbol in extra.sorted() {
            let name = fresh.first { $0.isin.caseInsensitiveCompare(symbol) == .orderedSame }?.title ?? symbol
            let phantom = TradeRepublicPosition(isin: symbol, name: name, quantity: 0, averageBuyInCents: nil)
            let added = appendBuys(
                position: phantom,
                holding: nil,
                activities: fresh,
                history: activities,
                giftDates: giftDates,
                now: now,
                into: &moves
            )
            let sales = trades(isin: symbol, activities: fresh, buying: false, after: nil)
            if !sales.isEmpty {
                if added > 0.001 {
                    appendSales(
                        quantity: added,
                        position: phantom,
                        holding: HeldPosition(
                            symbol: symbol,
                            name: name,
                            quantity: added,
                            purchasePriceCents: 0,
                            latestLotDate: nil
                        ),
                        activities: fresh,
                        now: now,
                        into: &moves
                    )
                } else {
                    appendLots(
                        delta: sales.reduce(0) { $0 + ($1.quantity ?? 0) },
                        events: sales,
                        buying: false,
                        isin: symbol,
                        name: name,
                        cost: 0,
                        now: now,
                        into: &moves
                    )
                }
                moves.append(.drop(isin: symbol))
            }
        }
        return moves
    }

    /// A position the session no longer returns is dropped only when the history has a matching sale.
    /// Without a sale event the holding stays. A leftover quantity is not booked as a sale dated today.
    private static func appendExit(
        _ holding: HeldPosition,
        symbol: String,
        activities: [TradeRepublicActivity],
        known: Set<String>,
        now: Date,
        into moves: inout [TradeRepublicMove]
    ) {
        guard holding.quantity > 0.0000005 else {
            moves.append(.drop(isin: symbol))
            return
        }
        let sales = exitSales(symbol: symbol, name: holding.name, activities: activities)
        let unseen = sales.filter { !known.contains(TradeRepublicTimeline.fingerprint($0.id)) }
        if !unseen.isEmpty {
            appendLots(
                delta: holding.quantity,
                events: unseen,
                buying: false,
                isin: symbol,
                name: holding.name,
                cost: holding.purchasePriceCents,
                now: now,
                into: &moves
            )
        } else if !sales.isEmpty {
            moves.append(.drop(isin: symbol))
        }
    }

    private static func exitSales(symbol: String, name: String, activities: [TradeRepublicActivity]) -> [TradeRepublicActivity] {
        activities.filter { claimsSale(symbol: symbol, name: name, item: $0) }.sorted { $0.date < $1.date }
    }

    private static func claimsSale(_ holding: HeldPosition, item: TradeRepublicActivity) -> Bool {
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return claimsSale(symbol: symbol, name: holding.name, item: item)
    }

    private static func claimsSale(symbol: String, name: String, item: TradeRepublicActivity) -> Bool {
        guard item.trade, item.amountCents > 0 else { return false }
        if !item.isin.isEmpty && item.isin.caseInsensitiveCompare(symbol) == .orderedSame { return true }
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !named.isEmpty && item.title.localizedCaseInsensitiveContains(named)
    }

    @discardableResult
    private static func appendBuys(
        position: TradeRepublicPosition,
        holding: HeldPosition?,
        activities: [TradeRepublicActivity],
        history: [TradeRepublicActivity],
        giftDates: [String: Date],
        now: Date,
        into moves: inout [TradeRepublicMove]
    ) -> Double {
        let symbol = position.isin.uppercased()
        let name = position.name.isEmpty ? (holding?.name ?? symbol) : position.name
        let giftEvents = history.filter {
            ($0.isGrant || ($0.amountCents == 0 && !$0.trade))
                && matchesInstrument($0, isin: symbol, name: name)
        }.sorted { $0.date < $1.date }
        let given = giftEvents.filter { ($0.quantity ?? 0) > 0.0000005 }
        for event in given {
            let quantity = event.quantity ?? 0
            let gift = event.statementType != "Cashback"
            let value = abs(event.amountCents)
            let shown = gift ? 0 : (value > 0 ? value : Int((quantity * Double(position.averageBuyInCents ?? 0)).rounded()))
            moves.append(.grant(
                id: event.id,
                date: event.date,
                title: event.title.isEmpty ? name : event.title,
                isin: symbol,
                name: name,
                quantity: quantity,
                amountCents: shown,
                statementType: event.statementType.isEmpty ? "Depotgeschenk" : event.statementType
            ))
        }
        let chosen = trades(isin: symbol, activities: activities, buying: true, after: nil)
        var sized = chosen.filter { purchase($0, averageCents: position.averageBuyInCents ?? 0) }
        let saleEvents = trades(isin: symbol, activities: history, buying: false, after: nil)
        var covered = sized.reduce(0.0) { $0 + ($1.quantity ?? 0) } + given.reduce(0.0) { $0 + ($1.quantity ?? 0) }
        if holding == nil, saleEvents.isEmpty, position.quantity > 0.0000005, covered > position.quantity + 0.001 {
            let factor = position.quantity / covered
            sized = sized.map { event in
                var copy = event
                copy.quantity = (event.quantity ?? 0) * factor
                return copy
            }
            covered = position.quantity
        }
        for event in sized {
            moves.append(.buy(
                id: event.id,
                date: event.date,
                title: event.title.isEmpty ? name : event.title,
                isin: symbol,
                name: name,
                quantity: event.quantity ?? 0,
                amountCents: event.amountCents,
                savingsPlan: event.savingsPlan
            ))
        }
        let rest = position.quantity - (holding?.quantity ?? 0) - covered
        guard rest > 0.001 else { return covered }
        let oldest = (sized + given).map(\.date).min() ?? history.map(\.date).min() ?? now
        let date = Calendar.current.date(byAdding: .day, value: -1, to: oldest) ?? oldest
        let cost = position.averageBuyInCents ?? 0
        let bought = history.contains {
            $0.isin.caseInsensitiveCompare(symbol) == .orderedSame && purchase($0, averageCents: cost)
        }
        if !bought {
            let giftDate = given.map(\.date).min() ?? giftEvents.map(\.date).min() ?? giftDates[symbol] ?? date
            moves.append(.grant(
                id: "gift-\(symbol)",
                date: giftDate,
                title: name,
                isin: symbol,
                name: name,
                quantity: rest,
                amountCents: 0,
                statementType: "Depotgeschenk"
            ))
            return covered + rest
        }
        guard cost > 0 else { return covered }
        moves.append(.shares(
            id: "open-\(symbol)",
            date: date,
            isin: symbol,
            name: name,
            quantity: rest,
            unitCents: cost
        ))
        return covered + rest
    }

    static func giftDates(
        positions: [TradeRepublicPosition],
        activities: [TradeRepublicActivity]
    ) -> [String: Date] {
        var unused = activities.filter {
            $0.isGrant || ($0.amountCents == 0 && !$0.trade)
        }.sorted { $0.date < $1.date }
        let gifts = positions.filter { position in
            !activities.contains {
                $0.isin.caseInsensitiveCompare(position.isin) == .orderedSame
                    && purchase($0, averageCents: position.averageBuyInCents ?? 0)
            }
        }
        var dates: [String: Date] = [:]
        for position in gifts {
            let symbol = position.isin.uppercased()
            if let event = unused.first(where: { matchesInstrument($0, isin: position.isin, name: position.name) }) {
                dates[symbol] = event.date
                unused.removeAll { $0.id == event.id }
            }
        }
        let remaining = gifts.filter { dates[$0.isin.uppercased()] == nil }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for (position, event) in zip(remaining, unused) {
            dates[position.isin.uppercased()] = event.date
        }
        return dates
    }

    static func matchesInstrument(_ item: TradeRepublicActivity, isin: String, name: String) -> Bool {
        let symbol = isin.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isin.isEmpty, !symbol.isEmpty, item.isin.caseInsensitiveCompare(symbol) == .orderedSame {
            return true
        }
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard named.count >= 4, titled.count >= 4 else { return false }
        return titled.localizedStandardContains(named) || named.localizedStandardContains(titled)
    }

    private static func appendSales(
        quantity: Double,
        position: TradeRepublicPosition,
        holding: HeldPosition,
        activities: [TradeRepublicActivity],
        now: Date,
        into moves: inout [TradeRepublicMove]
    ) {
        let symbol = position.isin.uppercased()
        let name = position.name.isEmpty ? holding.name : position.name
        let chosen = trades(isin: symbol, activities: activities, buying: false, after: nil)
        if chosen.isEmpty { return }
        appendLots(delta: quantity, events: chosen, buying: false, isin: symbol, name: name, cost: holding.purchasePriceCents, now: now, into: &moves)
    }

    private static func appendLots(
        delta: Double,
        events: [TradeRepublicActivity],
        buying: Bool,
        isin: String,
        name: String,
        cost: Int,
        now: Date,
        into moves: inout [TradeRepublicMove]
    ) {
        let chosen = events.isEmpty ? [] : events
        if !chosen.isEmpty, chosen.allSatisfy({ ($0.quantity ?? 0) > 0.0000005 }) {
            for event in chosen {
                moves.append(lot(
                    id: event.id,
                    date: event.date,
                    title: event.title.isEmpty ? name : event.title,
                    isin: isin,
                    name: name,
                    quantity: event.quantity ?? 0,
                    amountCents: event.amountCents,
                    buying: buying
                ))
            }
            return
        }
        if chosen.isEmpty {
            guard buying, delta > 0.0000005 else { return }
            let amount = Int((delta * Double(cost)).rounded())
            moves.append(lot(id: "delta-\(isin)-buy", date: now, title: name, isin: isin, name: name, quantity: delta, amountCents: -amount, buying: true))
            return
        }
        let weights = chosen.map { max(Double(abs($0.amountCents)), 1) }
        let sum = weights.reduce(0, +)
        var used = 0.0
        for (index, event) in chosen.enumerated() {
            let quantity = index == chosen.count - 1 ? delta - used : (delta * weights[index] / sum)
            used += quantity
            guard quantity > 0.0000005 else { continue }
            moves.append(lot(
                id: event.id,
                date: event.date,
                title: event.title.isEmpty ? name : event.title,
                isin: isin,
                name: name,
                quantity: quantity,
                amountCents: event.amountCents,
                buying: buying
            ))
        }
    }

    private static func lot(
        id: String,
        date: Date,
        title: String,
        isin: String,
        name: String,
        quantity: Double,
        amountCents: Int,
        buying: Bool
    ) -> TradeRepublicMove {
        if buying {
            return .buy(id: id, date: date, title: title, isin: isin, name: name, quantity: quantity, amountCents: amountCents, savingsPlan: false)
        }
        return .sale(id: id, date: date, title: title, isin: isin, name: name, quantity: quantity, amountCents: amountCents)
    }

    /// Buys or sales for one ISIN, oldest first. With a latest lot date, only later events count.
    /// Without one, every event counts. A buy keeps its own share count instead of the position delta.
    private static func trades(
        isin: String,
        activities: [TradeRepublicActivity],
        buying: Bool,
        after latest: Date?
    ) -> [TradeRepublicActivity] {
        let rows = activities.filter { item in
            item.trade && item.isin.caseInsensitiveCompare(isin) == .orderedSame && (buying ? item.amountCents < 0 : item.amountCents > 0)
        }.sorted { $0.date < $1.date }
        if let latest {
            return rows.filter { $0.date > latest }
        }
        return rows
    }
}

enum TradeRepublicPlans {
    static func read(text: String) -> [TradeRepublicPlan] {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8))
        else { return [] }
        var found: [TradeRepublicPlan] = []
        collect(object, into: &found)
        var byISIN: [String: TradeRepublicPlan] = [:]
        for plan in found {
            let key = plan.isin.uppercased()
            if let existing = byISIN[key], existing.active, !plan.active { continue }
            byISIN[key] = plan
        }
        return byISIN.values.sorted { $0.isin < $1.isin }
    }

    static func cadence(for interval: String) -> Cadence {
        let folded = interval.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if folded.contains("second") || folded.contains("two") || folded.contains("bi") { return .biweekly }
        if folded.contains("week") { return .weekly }
        if folded.contains("year") { return .yearly }
        return .monthly
    }

    private static func collect(_ object: Any, into found: inout [TradeRepublicPlan]) {
        if let row = object as? [String: Any] {
            if let plan = plan(from: row) { found.append(plan) }
            for value in row.values { collect(value, into: &found) }
        } else if let list = object as? [Any] {
            for value in list { collect(value, into: &found) }
        }
    }

    private static func plan(from row: [String: Any]) -> TradeRepublicPlan? {
        let isin = ((row["instrumentId"] as? String) ?? (row["isin"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard isin.count == 12 else { return nil }
        let interval = (row["interval"] as? String) ?? ""
        guard !interval.isEmpty else { return nil }
        guard let amount = cents(row["amount"]), amount > 0 else { return nil }
        let status = ((row["status"] as? String) ?? "ACTIVE").uppercased()
        let inactive = status.contains("CANCEL") || status.contains("DELETE") || status.contains("PAUSE") || status.contains("INACTIVE")
        let name = ((row["name"] as? String) ?? (row["instrumentName"] as? String) ?? (row["title"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TradeRepublicPlan(isin: isin, name: name, amountCents: amount, interval: interval, active: !inactive)
    }

    private static func cents(_ value: Any?) -> Int? {
        if let row = value as? [String: Any] {
            let number: Double?
            switch row["value"] {
            case let amount as Double: number = amount
            case let amount as Int: number = Double(amount)
            case let amount as NSNumber: number = amount.doubleValue
            case let text as String: number = Double(text.replacingOccurrences(of: ",", with: "."))
            default: number = nil
            }
            guard let number else { return nil }
            let digits = (row["fractionDigits"] as? Int) ?? (row["fractionDigits"] as? NSNumber)?.intValue ?? 2
            return Int((number * pow(10, Double(digits))).rounded())
        }
        if let number = value as? Double { return Int((number * 100).rounded()) }
        if let number = value as? Int { return number * 100 }
        if let number = value as? NSNumber { return Int((number.doubleValue * 100).rounded()) }
        return nil
    }
}
