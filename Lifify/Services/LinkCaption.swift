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
}
