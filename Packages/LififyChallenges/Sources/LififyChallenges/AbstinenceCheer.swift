import Foundation
import LififyCore

/// The abstinence push. The title is the cheer. The body still names the challenge, the step, and the coins.
public enum AbstinenceCheer {
    public static func title(for milestone: AbstinenceMilestone) -> String {
        switch milestone {
        case .hour1: L("Los geht's!", "Here we go!")
        case .hour2: L("Weiter so!", "Keep going!")
        case .hour4: L("Schon vier Stunden!", "Four hours already!")
        case .hour8: L("Acht Stunden, stark!", "Eight hours, nice!")
        case .hour24: L("Ein ganzer Tag!", "A whole day!")
        case .hour72: L("Drei Tage am Stück!", "Three days straight!")
        case .day7: L("Eine Woche!", "One week!")
        case .day14: L("Zwei Wochen!", "Two weeks!")
        case .day30: L("Ein ganzer Monat!", "A whole month!")
        case .year1: L("Ein ganzes Jahr!", "A whole year!")
        }
    }

    public static func line(for milestone: AbstinenceMilestone) -> String {
        switch milestone {
        case .hour1: L("Die erste Stunde sitzt.", "The first hour is yours.")
        case .hour2: L("Zwei Stunden, du bleibst dran.", "Two hours, and you're still in.")
        case .hour4: L("Vier Stunden. Das fühlt sich gut an.", "Four hours. That feels good.")
        case .hour8: L("Acht Stunden. Richtig stark.", "Eight hours. Really strong.")
        case .hour24: L("Ein ganzer Tag. Darauf kannst du stolz sein.", "A whole day. Be proud of that.")
        case .hour72: L("Drei Tage hintereinander. Weiter so.", "Three days in a row. Keep it up.")
        case .day7: L("Eine Woche. Das ist ein echter Lauf.", "One week. That is a real run.")
        case .day14: L("Zwei Wochen. Du bist im Rhythmus.", "Two weeks. You're in the rhythm.")
        case .day30: L("Ein Monat. Das ist groß.", "One month. That is big.")
        case .year1: L("Ein Jahr. Das ist riesig.", "One year. That is huge.")
        }
    }

    public static func body(challenge: String, milestone: AbstinenceMilestone, coins: Int) -> String {
        let fact = "\(challenge) · \(milestone.label). \(line(for: milestone))"
        guard coins > 0 else { return fact }
        return "\(fact) +\(coins) \(L("Coins für dich", "coins for you"))."
    }
}
