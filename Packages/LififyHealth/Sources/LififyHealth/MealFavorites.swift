import Foundation
import LififyCore

/// A meal that can be entered again with one tap.
public struct MealTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var nutrients: [String: Double]
    public var kindRaw: String

    /// Creates a template from a logged meal. Meals with the same name share one template.
    public init(meal: MealRecord) {
        id = MealFavorites.key(for: meal.title)
        title = meal.title
        nutrients = meal.nutrients
        kindRaw = meal.kindRaw
    }

    /// The calories of the meal, rounded.
    public var calories: Int {
        Int((nutrients[Nutrient.calories.rawValue] ?? 0).rounded())
    }
}

/// Stores favorite meals and finds recently eaten ones.
@MainActor
public enum MealFavorites {
    /// The identity of a meal name, ignoring case, accents, and outer spaces.
    public nonisolated static func key(for title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    /// Returns all favorites by name.
    public static func all() -> [MealTemplate] {
        LinkTable.decoded(.mealFavorites, as: MealTemplate.self).values
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Says whether a meal's name is a favorite.
    public static func contains(_ meal: MealRecord) -> Bool {
        LinkTable.map(.mealFavorites)[key(for: meal.title)] != nil
    }

    /// Adds a meal to the favorites, or removes it.
    public static func toggle(_ meal: MealRecord) {
        let id = key(for: meal.title)
        guard !id.isEmpty else { return }
        var values = LinkTable.decoded(.mealFavorites, as: MealTemplate.self)
        values[id] = values[id] == nil ? MealTemplate(meal: meal) : nil
        LinkTable.replaceEncoded(.mealFavorites, with: values)
    }

    /// Lists recently confirmed meals that are not favorites, newest first and once per name.
    ///
    /// - Parameters:
    ///   - meals: All logged meals.
    ///   - limit: The maximum number of entries.
    /// - Returns: Templates of the recent meals.
    public static func recent(in meals: [MealRecord], limit: Int = 5) -> [MealTemplate] {
        var seen = Set(all().map(\.id))
        var result: [MealTemplate] = []
        for meal in meals.sorted(by: { $0.createdAt > $1.createdAt }) where meal.status == .confirmed {
            let id = key(for: meal.title)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            result.append(MealTemplate(meal: meal))
            if result.count == limit { break }
        }
        return result
    }

    /// Builds a confirmed new meal from a template. Its photo and fast-food charge are not copied.
    public static func meal(from template: MealTemplate, dayKey: String, now: Date = .now) -> MealRecord {
        MealRecord(
            dayKey: dayKey,
            title: template.title,
            createdAt: now,
            source: .manual,
            status: .confirmed,
            nutrients: template.nutrients,
            kind: MealKind.resolved(template.kindRaw)
        )
    }

    /// Exports the favorites as JSON for a backup.
    public static func exportJSON() -> String {
        guard let data = try? JSONEncoder().encode(all()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Replaces the favorites from a backup.
    public static func restore(json: String) {
        let templates = (try? JSONDecoder().decode([MealTemplate].self, from: Data(json.utf8))) ?? []
        LinkTable.replaceEncoded(.mealFavorites, with: Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    /// Removes all favorites.
    public static func reset() {
        LinkTable.clear(.mealFavorites)
    }
}
