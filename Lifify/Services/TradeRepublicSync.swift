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
    /// Share count from the timeline row or its detail. Missing means the row must not invent one.
    var quantity: Double? = nil
    var savingsPlan: Bool = false
}

struct TradeRepublicSnapshot: Equatable, Sendable {
    var positions: [TradeRepublicPosition]
    var activities: [TradeRepublicActivity]
}

struct HeldPosition: Equatable {
    var symbol: String
    var name: String
    var quantity: Double
    var purchasePriceCents: Int
    var latestLotDate: Date?
}

enum TradeRepublicMove: Equatable {
    case cash(id: String, date: Date, title: String, amountCents: Int)
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
        let after = (object["cursors"] as? [String: Any])?["after"] as? String
        return (rows.compactMap(activity), after)
    }

    static func fingerprint(_ id: String) -> String { "tr-\(id)" }

    private static func activity(_ row: [String: Any]) -> TradeRepublicActivity? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        let status = (row["status"] as? String) ?? ""
        guard status.caseInsensitiveCompare("EXECUTED") == .orderedSame else { return nil }
        guard let date = date(from: (row["timestamp"] as? String) ?? "") else { return nil }
        let amount = cents(row["amount"] as? [String: Any]) ?? 0
        guard amount != 0 else { return nil }
        let eventType = (row["eventType"] as? String) ?? ""
        let isin = isin(from: (row["icon"] as? String) ?? "")
        let title = ((row["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return TradeRepublicActivity(
            id: id,
            date: date,
            title: title,
            eventType: eventType,
            amountCents: amount,
            isin: isin,
            trade: isTrade(eventType, isin: isin),
            status: status,
            quantity: shareCount(row),
            savingsPlan: isSavingsPlan(eventType)
        )
    }

    static func enrich(_ item: TradeRepublicActivity, detail text: String) -> TradeRepublicActivity {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let object = try? JSONSerialization.jsonObject(with: Data(text[start...].utf8))
        else { return item }
        var copy = item
        if let shares = labeledNumber(in: object, titles: ["share", "stück", "stueck", "anteil", "quantity", "anteile"]) {
            copy.quantity = shares
        }
        if let symbol = labeledText(in: object, titles: ["isin"]), !symbol.isEmpty {
            copy.isin = symbol
            copy.trade = true
        }
        if treeMentionsSavings(object) { copy.savingsPlan = true }
        return copy
    }

    private static func isSavingsPlan(_ eventType: String) -> Bool {
        let folded = eventType.uppercased().replacingOccurrences(of: "_", with: "")
        return folded.contains("SAVINGSPLAN") || folded.contains("SAVINGPLAN")
    }

    private static func isTrade(_ eventType: String, isin: String) -> Bool {
        guard !isin.isEmpty else { return false }
        let folded = eventType.uppercased()
        if folded.contains("DIVIDEND") || folded.contains("INTEREST") || folded.contains("CARD")
            || folded.contains("BANK") || folded.contains("PAYMENT") {
            return false
        }
        return folded.contains("ORDER") || folded.contains("TRADING") || folded.contains("SAVING") || folded.contains("SAVE")
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

    private static func labeledNumber(in object: Any, titles: [String]) -> Double? {
        guard let text = labeledText(in: object, titles: titles) else { return nil }
        return number(in: text, unit: false)
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

    private static func treeMentionsSavings(_ object: Any) -> Bool {
        if let text = object as? String {
            let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            return folded.contains("sparplan") || folded.contains("savings plan") || folded.contains("savingsplan")
        }
        if let row = object as? [String: Any] {
            return row.values.contains { treeMentionsSavings($0) }
        }
        if let list = object as? [Any] {
            return list.contains { treeMentionsSavings($0) }
        }
        return false
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
            if item.amountCents > 0 && leaving.contains(where: { claimsSale($0, item: item) }) { continue }
            let title = item.title.isEmpty ? "Trade Republic" : item.title
            moves.append(.cash(id: item.id, date: item.date, title: title, amountCents: item.amountCents))
        }
        var seen = Set<String>()
        for holding in holdings {
            let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !symbol.isEmpty else { continue }
            seen.insert(symbol)
            guard let position = live[symbol] else {
                appendExit(holding, symbol: symbol, activities: activities, known: known, now: now, into: &moves)
                continue
            }
            let delta = position.quantity - holding.quantity
            if delta > 0.0000005 {
                appendBuys(position: position, holding: holding, activities: fresh, now: now, into: &moves)
            } else if delta < -0.0000005 {
                appendSales(quantity: -delta, position: position, holding: holding, activities: fresh, now: now, into: &moves)
            }
        }
        for (symbol, position) in live where !seen.contains(symbol) {
            appendBuys(position: position, holding: nil, activities: fresh, now: now, into: &moves)
        }
        return moves
    }

    /// A position the session no longer returns was sold. Book that sale, then remove it.
    /// The timeline's proceeds and date are used when a matching sale is present.
    /// Otherwise the remaining shares are sold at their cost basis, so the position does not vanish without a booking.
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
        } else if sales.isEmpty {
            appendLots(
                delta: holding.quantity,
                events: [],
                buying: false,
                isin: symbol,
                name: holding.name,
                cost: holding.purchasePriceCents,
                now: now,
                into: &moves
            )
        }
        moves.append(.drop(isin: symbol))
    }

    private static func exitSales(symbol: String, name: String, activities: [TradeRepublicActivity]) -> [TradeRepublicActivity] {
        activities.filter { claimsSale(symbol: symbol, name: name, item: $0) }.sorted { $0.date < $1.date }
    }

    private static func claimsSale(_ holding: HeldPosition, item: TradeRepublicActivity) -> Bool {
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return claimsSale(symbol: symbol, name: holding.name, item: item)
    }

    private static func claimsSale(symbol: String, name: String, item: TradeRepublicActivity) -> Bool {
        guard item.amountCents > 0 else { return false }
        if !item.isin.isEmpty && item.isin.caseInsensitiveCompare(symbol) == .orderedSame { return true }
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !named.isEmpty && item.title.localizedCaseInsensitiveContains(named)
    }

    private static func appendBuys(
        position: TradeRepublicPosition,
        holding: HeldPosition?,
        activities: [TradeRepublicActivity],
        now: Date,
        into moves: inout [TradeRepublicMove]
    ) {
        let symbol = position.isin.uppercased()
        let name = position.name.isEmpty ? (holding?.name ?? symbol) : position.name
        let chosen = trades(isin: symbol, activities: activities, buying: true, after: holding?.latestLotDate)
        let sized = chosen.filter { ($0.quantity ?? 0) > 0.0000005 }
        if !sized.isEmpty {
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
            return
        }
        guard holding == nil else { return }
        let newest = chosen.last
        let cost = position.averageBuyInCents ?? 0
        let amount = cost > 0 ? -Int((position.quantity * Double(cost)).rounded()) : (newest?.amountCents ?? 0)
        moves.append(.buy(
            id: newest?.id ?? "open-\(symbol)",
            date: newest?.date ?? now,
            title: newest?.title ?? name,
            isin: symbol,
            name: name,
            quantity: position.quantity,
            amountCents: amount,
            savingsPlan: newest?.savingsPlan ?? false
        ))
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
        let chosen = trades(isin: symbol, activities: activities, buying: false, after: holding.latestLotDate)
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
            let amount = Int((delta * Double(cost)).rounded())
            let signed = buying ? -amount : amount
            let move = lot(id: "delta-\(isin)-\(buying ? "buy" : "sale")", date: now, title: name, isin: isin, name: name, quantity: delta, amountCents: signed, buying: buying)
            moves.append(move)
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
