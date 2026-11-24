import Foundation
import LififyCore

/// The evening note of the calorie challenge: how the day stands against the body goal.
public enum CalorieNudge {
    /// A notification's title and text.
    public struct Note: Equatable, Sendable {
        public let title: String
        public let body: String
    }

    /// Words the day's calories for the goal.
    ///
    /// Losing fat keeps under the target, building muscle has to reach it, and maintaining stays
    /// inside 90 to 110 percent, the same rule that pays the challenge.
    ///
    /// - Parameters:
    ///   - goal: The body goal.
    ///   - target: The day's calorie target.
    ///   - eaten: The confirmed calories of the day.
    /// - Returns: The note, or `nil` without a target.
    public static func note(goal: BodyGoal, target: Int?, eaten: Int) -> Note? {
        guard let target, target > 0 else { return nil }
        guard eaten > 0 else { return empty(goal: goal, target: target) }
        switch goal {
        case .loseFat: return deficit(target: target, eaten: eaten)
        case .gainMuscle: return surplus(target: target, eaten: eaten)
        case .maintain: return maintain(target: target, eaten: eaten)
        }
    }

    /// No meal entered yet.
    private static func empty(goal: BodyGoal, target: Int) -> Note {
        let aim = switch goal {
        case .loseFat: L("höchstens \(target) kcal", "at most \(target) kcal")
        case .gainMuscle: L("mindestens \(target) kcal", "at least \(target) kcal")
        case .maintain: L("rund \(target) kcal", "about \(target) kcal")
        }
        return Note(
            title: L("Ernährung", "Nutrition"),
            body: L("Noch keine Mahlzeit eingetragen. Dein Ziel heute: \(aim).", "No meal entered yet. Your goal today: \(aim).")
        )
    }

    /// Losing fat: under the target is good.
    private static func deficit(target: Int, eaten: Int) -> Note {
        guard eaten <= target else {
            return Note(
                title: L("Etwas drüber", "A little over"),
                body: L("\(eaten) von \(target) kcal, \(eaten - target) kcal über dem Ziel. Morgen ist ein neuer Tag.",
                        "\(eaten) of \(target) kcal, \(eaten - target) kcal over the goal. Tomorrow is a new day.")
            )
        }
        return Note(
            title: L("Bisher gut gemacht", "Well done so far"),
            body: L("\(eaten) von \(target) kcal. Du hast noch \(target - eaten) kcal Luft.",
                    "\(eaten) of \(target) kcal. You still have \(target - eaten) kcal to spare.")
        )
    }

    /// Building muscle: the target has to be reached.
    private static func surplus(target: Int, eaten: Int) -> Note {
        guard eaten < target else {
            return Note(
                title: L("Ziel erreicht", "Goal reached"),
                body: L("\(eaten) von \(target) kcal. Stark, genug Energie für den Aufbau.", "\(eaten) of \(target) kcal. Strong, enough energy to build.")
            )
        }
        return Note(
            title: L("Da geht noch was rein", "Room for more"),
            body: L("\(eaten) von \(target) kcal. Es fehlen noch \(target - eaten) kcal, hau rein.",
                    "\(eaten) of \(target) kcal. \(target - eaten) kcal still to go, eat up.")
        )
    }

    /// Maintaining: inside 90 to 110 percent.
    private static func maintain(target: Int, eaten: Int) -> Note {
        let low = NutritionPlan.percent(target, 90)
        let high = NutritionPlan.percent(target, 110)
        if eaten < low {
            return Note(
                title: L("Noch etwas offen", "A bit to go"),
                body: L("\(eaten) von \(target) kcal. Noch \(low - eaten) kcal bis zum Zielbereich.", "\(eaten) of \(target) kcal. \(low - eaten) kcal to reach the range.")
            )
        }
        if eaten > high {
            return Note(
                title: L("Etwas drüber", "A little over"),
                body: L("\(eaten) kcal, \(eaten - high) kcal über dem Zielbereich.", "\(eaten) kcal, \(eaten - high) kcal above the range.")
            )
        }
        return Note(
            title: L("Im Zielbereich", "In range"),
            body: L("\(eaten) von \(target) kcal. Genau richtig.", "\(eaten) of \(target) kcal. Just right.")
        )
    }
}
