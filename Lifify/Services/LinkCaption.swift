import Foundation

enum LinkCaption {
    static func challenge(_ title: String) -> String {
        L("Mit Challenge \(title) verknüpft", "Linked to challenge \(title)")
    }

    static func group(_ title: String) -> String {
        L("Mit Gruppe \(title) verknüpft", "Linked to group \(title)")
    }

    static func reward(_ title: String) -> String {
        L("Mit Belohnung \(title) verknüpft", "Linked to reward \(title)")
    }

    /// One title uses the single-challenge caption. Several are listed together.
    static func challenges(_ titles: [String], fallback: String? = nil) -> String? {
        let names = titles.filter { !$0.isEmpty }
        if names.count == 1 { return challenge(names[0]) }
        if names.count > 1 {
            return L(
                "Mit Challenges \(countedTitles(names)) verknüpft",
                "Linked to challenges \(countedTitles(names))"
            )
        }
        if let fallback, !fallback.isEmpty { return challenge(fallback) }
        return nil
    }

    static func calendar(titles: [String], count: Int, singleDate: Date?) -> String? {
        let unique = Array(Set(titles.filter { !$0.isEmpty })).sorted()
        guard let first = unique.first else { return nil }
        if unique.count == 1, count == 1, let singleDate {
            let when = AppDate.numeric(singleDate)
            return L("Mit Kalender \(first) · \(when) verknüpft", "Linked to calendar \(first) · \(when)")
        }
        if unique.count == 1 {
            return L("Mit Kalender \(first) · \(count) verknüpft", "Linked to calendar \(first) · \(count)")
        }
        let names = unique.prefix(3).joined(separator: ", ")
        return L("Mit Kalender \(names) verknüpft", "Linked to calendar \(names)")
    }

    /// Collapses repeated titles. Twelve events named Gym become "Gym · 12".
    static func countedTitles(_ titles: [String]) -> String {
        var counts: [String: Int] = [:]
        for title in titles where !title.isEmpty {
            counts[title, default: 0] += 1
        }
        return counts.keys.sorted().map { title in
            let count = counts[title] ?? 0
            return count > 1 ? "\(title) · \(count)" : title
        }.joined(separator: ", ")
    }
}
