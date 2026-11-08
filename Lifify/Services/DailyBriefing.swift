import Foundation

struct DailyBriefingLine: Equatable {
    var title: String
    var detail: String
}

/// The text of the daily push. It only formats values it is given.
enum DailyBriefing {
    static func text(
        events: [DailyBriefingLine],
        challenges: [DailyBriefingLine],
        rewards: [DailyBriefingLine],
        salary: String?,
        expenses: [DailyBriefingLine]
    ) -> String {
        var lines: [String] = []
        if !events.isEmpty {
            lines.append(labeled(L("Termine", "Events"), events))
        }
        if !challenges.isEmpty {
            lines.append(labeled(L("Challenges", "Challenges"), challenges))
        }
        if !rewards.isEmpty {
            lines.append(labeled(L("Belohnungen", "Rewards"), rewards))
        }
        if let salary, !salary.isEmpty {
            lines.append("\(L("Gehalt", "Salary")): \(salary)")
        }
        if !expenses.isEmpty {
            lines.append(labeled(L("Ausgaben", "Expenses"), expenses))
        }
        if lines.isEmpty {
            return L("Heute steht nichts an.", "Nothing is scheduled today.")
        }
        let joined = lines.joined(separator: "\n")
        if joined.count <= 500 { return joined }
        return String(joined.prefix(497)) + "…"
    }

    /// A bonus reached before real time, or one nobody queued, should notify now.
    static func shouldDeliverBonusNow(due: Date, realNow: Date, alreadyQueued: Bool) -> Bool {
        if due > realNow { return true }
        return !alreadyQueued
    }

    private static func labeled(_ title: String, _ lines: [DailyBriefingLine]) -> String {
        let body = lines.prefix(4).map { line in
            line.detail.isEmpty ? line.title : "\(line.title) \(line.detail)"
        }.joined(separator: ", ")
        return "\(title): \(body)"
    }
}
