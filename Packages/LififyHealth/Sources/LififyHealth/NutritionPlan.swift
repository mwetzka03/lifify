import Foundation
import LififyChallenges
import LififyCore
import SwiftData

/// Sex used by the calorie estimate. Unspecified uses the midpoint of the two formulas.
public enum BodySex: String, CaseIterable, Identifiable, Sendable {
    case female
    case male
    case unspecified

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .female: L("Weiblich", "Female")
        case .male: L("Männlich", "Male")
        case .unspecified: L("Keine Angabe", "Unspecified")
        }
    }

    /// Mifflin–St Jeor constant. Unspecified is the midpoint of +5 and −161.
    public var mifflinOffset: Double {
        switch self {
        case .male: 5
        case .female: -161
        case .unspecified: -78
        }
    }

    public var calorieFloor: Int {
        switch self {
        case .female: 1200
        case .male: 1500
        case .unspecified: 1350
        }
    }

    /// Reads a stored value.
    public static func resolved(_ raw: String) -> BodySex {
        BodySex(rawValue: raw) ?? .unspecified
    }
}

/// What the calorie target is aiming at.
public enum BodyGoal: String, CaseIterable, Identifiable, Sendable {
    case loseFat
    case maintain
    case gainMuscle

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .loseFat: L("Fett verlieren", "Lose fat")
        case .maintain: L("Halten", "Maintain")
        case .gainMuscle: L("Muskeln aufbauen", "Build muscle")
        }
    }

    /// Percent of the sedentary maintenance. 85 loses fat, 100 holds, 110 builds muscle.
    public var percent: Int {
        switch self {
        case .loseFat: 85
        case .maintain: 100
        case .gainMuscle: 110
        }
    }

    /// Reads a stored value.
    public static func resolved(_ raw: String) -> BodyGoal {
        BodyGoal(rawValue: raw) ?? .maintain
    }
}

/// Height, weight, sex, and goal.
public struct BodyMeasures: Equatable, Sendable {
    public var heightCm: Double
    public var weightKg: Double
    public var sex: BodySex
    public var goal: BodyGoal

    public var isComplete: Bool { heightCm > 0 && weightKg > 0 }

    public static let empty = BodyMeasures(heightCm: 0, weightKg: 0, sex: .unspecified, goal: .maintain)

    public init(heightCm: Double, weightKg: Double, sex: BodySex, goal: BodyGoal) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.sex = sex
        self.goal = goal
    }
}

/// Stores the body data.
public enum UserBody {
    public static let heightKey = "lifify.userHeightCm"
    public static let weightKey = "lifify.userWeightKg"
    public static let sexKey = "lifify.userSex"
    public static let goalKey = "lifify.userGoal"

    /// Returns the current body data.
    public static func current(defaults: UserDefaults = AppDefaults.store) -> BodyMeasures {
        BodyMeasures(
            heightCm: defaults.double(forKey: heightKey),
            weightKg: defaults.double(forKey: weightKey),
            sex: BodySex.resolved(defaults.string(forKey: sexKey) ?? ""),
            goal: BodyGoal.resolved(defaults.string(forKey: goalKey) ?? "")
        )
    }

    /// Formats the height for editing.
    public static func heightText(defaults: UserDefaults = AppDefaults.store) -> String {
        text(current(defaults: defaults).heightCm)
    }

    /// Formats the weight for editing.
    public static func weightText(defaults: UserDefaults = AppDefaults.store) -> String {
        text(current(defaults: defaults).weightKg)
    }

    /// Stores typed body data.
    public static func save(
        heightText: String,
        weightText: String,
        sex: BodySex,
        goal: BodyGoal,
        defaults: UserDefaults = AppDefaults.store
    ) {
        store(NutritionPlan.amount(from: heightText), key: heightKey, defaults: defaults)
        store(NutritionPlan.amount(from: weightText), key: weightKey, defaults: defaults)
        defaults.set(sex.rawValue, forKey: sexKey)
        defaults.set(goal.rawValue, forKey: goalKey)
    }

    /// Restores the body data from a backup.
    public static func restore(height: String, weight: String, sex: String, goal: String, defaults: UserDefaults = AppDefaults.store) {
        save(
            heightText: height,
            weightText: weight,
            sex: BodySex.resolved(sex),
            goal: BodyGoal.resolved(goal),
            defaults: defaults
        )
    }

    /// Removes the body data.
    public static func reset(defaults: UserDefaults = AppDefaults.store) {
        defaults.removeObject(forKey: heightKey)
        defaults.removeObject(forKey: weightKey)
        defaults.removeObject(forKey: sexKey)
        defaults.removeObject(forKey: goalKey)
    }

    /// Stores a positive value, or removes the key.
    private static func store(_ value: Double, key: String, defaults: UserDefaults) {
        if value > 0 {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Formats a value for editing.
    private static func text(_ value: Double) -> String {
        guard value > 0 else { return "" }
        let shown = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        if AppDefaults.store.string(forKey: "appLanguage") == "en" { return shown }
        return shown.replacingOccurrences(of: ".", with: ",")
    }
}

/// The tracked nutrients.
public enum Nutrient: String, CaseIterable, Identifiable, Sendable {
    case calories
    case protein
    case carbohydrate
    case fat
    case saturatedFat
    case omega3
    case omega6
    case fiber
    case vitaminD
    case vitaminB12
    case vitaminC
    case calcium
    case iron
    case magnesium

    public var id: String { rawValue }

    public var isPrimary: Bool {
        switch self {
        case .calories, .protein, .carbohydrate, .fat, .saturatedFat, .omega3, .omega6, .fiber: true
        default: false
        }
    }

    public var unit: String {
        switch self {
        case .calories: "kcal"
        case .vitaminD, .vitaminB12: "µg"
        case .calcium, .iron, .magnesium, .vitaminC: "mg"
        default: "g"
        }
    }

    public var label: String {
        switch self {
        case .calories: L("Kalorien", "Calories")
        case .protein: L("Eiweiß", "Protein")
        case .carbohydrate: L("Kohlenhydrate", "Carbohydrates")
        case .fat: L("Fett", "Fat")
        case .saturatedFat: L("Gesättigte Fettsäuren", "Saturated fat")
        case .omega3: L("Omega-3", "Omega-3")
        case .omega6: L("Omega-6", "Omega-6")
        case .fiber: L("Ballaststoffe", "Fiber")
        case .vitaminD: L("Vitamin D", "Vitamin D")
        case .vitaminB12: L("Vitamin B12", "Vitamin B12")
        case .vitaminC: L("Vitamin C", "Vitamin C")
        case .calcium: L("Kalzium", "Calcium")
        case .iron: L("Eisen", "Iron")
        case .magnesium: L("Magnesium", "Magnesium")
        }
    }
}

/// How a meal sits on the plate. Fast food is the shop purchase. Whole and balanced earn the clean-day bonus.
public enum MealKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case whole
    case balanced
    case hearty
    case sweet
    case fastFood
    case alcohol

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .whole: L("Unverarbeitet", "Whole food")
        case .balanced: L("Ausgewogen", "Balanced")
        case .hearty: L("Deftig", "Hearty")
        case .sweet: L("Süß", "Sweet")
        case .fastFood: L("Fast Food", "Fast food")
        case .alcohol: L("Alkohol", "Alcohol")
        }
    }

    /// Reads a meal kind from text.
    public static func resolved(_ raw: String) -> MealKind {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch cleaned {
        case "whole", "wholefood", "unverarbeitet": return .whole
        case "balanced", "ausgewogen": return .balanced
        case "hearty", "deftig": return .hearty
        case "sweet", "suess", "süß": return .sweet
        case "fastfood": return .fastFood
        case "alcohol", "alkohol": return .alcohol
        default: return .balanced
        }
    }
}

/// How a meal was entered.
public enum MealSource: String, Codable {
    case manual
    case photo
}

/// Whether a meal is confirmed.
public enum MealStatus: String, Codable {
    case draft
    case confirmed
}

/// One logged meal.
public struct MealRecord: Codable, Identifiable, Equatable {
    public var id: UUID
    public var dayKey: String
    public var title: String
    public var note: String
    public var correction: String
    public var createdAt: Date
    public var source: MealSource
    public var status: MealStatus
    public var photoName: String?
    public var nutrients: [String: Double]
    public var kindRaw: String
    public var chargeID: UUID?

    public var kind: MealKind {
        get { MealKind.resolved(kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        dayKey: String,
        title: String,
        note: String = "",
        correction: String = "",
        createdAt: Date = .now,
        source: MealSource,
        status: MealStatus,
        photoName: String? = nil,
        nutrients: [String: Double] = [:],
        kind: MealKind = .balanced,
        chargeID: UUID? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.title = title
        self.note = note
        self.correction = correction
        self.createdAt = createdAt
        self.source = source
        self.status = status
        self.photoName = photoName
        self.nutrients = nutrients
        self.kindRaw = kind.rawValue
        self.chargeID = chargeID
    }

    /// Returns the amount of a nutrient.
    public func amount(_ nutrient: Nutrient) -> Double {
        nutrients[nutrient.rawValue] ?? 0
    }

    /// The stored field names.
    private enum CodingKeys: String, CodingKey {
        case id, dayKey, title, note, correction, createdAt, source, status, photoName, nutrients, kindRaw, chargeID
    }

    /// Decodes a meal. Fields missing from older versions get defaults.
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        dayKey = try box.decode(String.self, forKey: .dayKey)
        title = try box.decode(String.self, forKey: .title)
        note = try box.decodeIfPresent(String.self, forKey: .note) ?? ""
        correction = try box.decodeIfPresent(String.self, forKey: .correction) ?? ""
        createdAt = try box.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        source = try box.decode(MealSource.self, forKey: .source)
        status = try box.decode(MealStatus.self, forKey: .status)
        photoName = try box.decodeIfPresent(String.self, forKey: .photoName)
        nutrients = try box.decodeIfPresent([String: Double].self, forKey: .nutrients) ?? [:]
        kindRaw = try box.decodeIfPresent(String.self, forKey: .kindRaw) ?? MealKind.balanced.rawValue
        chargeID = try box.decodeIfPresent(UUID.self, forKey: .chargeID)
    }

    /// Encodes a meal.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(dayKey, forKey: .dayKey)
        try box.encode(title, forKey: .title)
        try box.encode(note, forKey: .note)
        try box.encode(correction, forKey: .correction)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encode(source, forKey: .source)
        try box.encode(status, forKey: .status)
        try box.encodeIfPresent(photoName, forKey: .photoName)
        try box.encode(nutrients, forKey: .nutrients)
        try box.encode(kindRaw, forKey: .kindRaw)
        try box.encodeIfPresent(chargeID, forKey: .chargeID)
    }
}

/// Texts of the nutrition area.
public enum NutritionCopy {
    public static var recognitionPending: String {
        L("Die Erkennung ist noch nicht verbunden.", "Recognition is not connected yet.")
    }

    public static var recognitionFailed: String {
        L("Die Erkennung hat nicht geantwortet. Die Werte kannst du selbst setzen.", "Recognition did not answer. You can set the values yourself.")
    }

    public static var recognizing: String {
        L("Das Foto wird gelesen.", "The photo is being read.")
    }

    public static var emptyDay: String {
        L("Noch keine Mahlzeit an diesem Tag.", "No meal on this day yet.")
    }

    public static var calorieChallenge: String {
        challengeTitle(for: .loseFat)
    }

    /// The challenge title of a goal.
    public static func challengeTitle(for goal: BodyGoal) -> String {
        switch goal {
        case .loseFat: L("Kaloriendefizit", "Calorie deficit")
        case .maintain: L("Kalorien halten", "Hold calories")
        case .gainMuscle: L("Muskelaufbau", "Build muscle")
        }
    }

    public static let previousCalorieTitles = ["Unter dem Kalorienziel", "Under the calorie target"]

    public static var automaticTitles: [String] {
        previousCalorieTitles + [
            "Kaloriendefizit", "Calorie deficit",
            "Kalorien halten", "Hold calories",
            "Muskelaufbau", "Build muscle"
        ]
    }
}

/// A camera shot is kept in the app. It reaches the photo library only when this is on.
public enum MealCapture {
    public static let saveKey = "lifify.saveMealPhotos"

    /// Says whether a photo is also saved to the library.
    public static func keepsInLibrary(_ enabled: Bool) -> Bool { enabled }
}

/// Photo recognition follows the Gemini key stored under Health. See ERNAEHRUNG.md.
public enum MealRecognition {
    public static let keyAccount = "gemini.api.key"
    public static let model = "gemini-2.5-flash"

    public static var isConnected: Bool {
        connected(hasKey: !(KeychainStore.string(account: keyAccount) ?? "").isEmpty)
    }

    /// Recognition needs a stored key.
    public static func connected(hasKey: Bool) -> Bool { hasKey }
}

/// Coins for a day at or under the calorie target, and the shop price of fast food.
public enum MealScore {
    public static let baseCoins = 20
    public static let cleanBonus = 10
    public static let fastFoodPrice = 25

    /// The score points of a meal kind.
    public static func points(for kind: MealKind) -> Int {
        switch kind {
        case .whole: 2
        case .balanced: 1
        case .hearty: 0
        case .sweet: -1
        case .alcohol: -1
        case .fastFood: -2
        }
    }

    /// Says whether a day contains fast food.
    public static func buysFastFood(_ kinds: [MealKind]) -> Bool {
        kinds.contains(.fastFood)
    }

    /// Lose fat stays at or under the target. Build muscle has to reach it.
    /// Maintain stays inside 90 to 110 percent. An empty day never qualifies.
    public static func qualifies(eaten: Int, target: Int?, goal: BodyGoal) -> Bool {
        guard let target, target > 0, eaten > 0 else { return false }
        switch goal {
        case .loseFat:
            return eaten <= target
        case .gainMuscle:
            return eaten >= target
        case .maintain:
            let low = NutritionPlan.percent(target, 90)
            let high = NutritionPlan.percent(target, 110)
            return eaten >= low && eaten <= high
        }
    }

    /// Taking an award back subtracts it from the balance, even below zero.
    public static func balance(afterRemoving awarded: Int, from balance: Int) -> Int {
        balance - awarded
    }

    /// Zero when the day misses the goal. A day of only whole and balanced meals adds the clean bonus.
    public static func coins(eaten: Int, target: Int?, kinds: [MealKind], goal: BodyGoal = .loseFat) -> Int {
        guard qualifies(eaten: eaten, target: target, goal: goal) else { return 0 }
        let clean = !kinds.isEmpty && kinds.allSatisfy { points(for: $0) > 0 }
        return baseCoins + (clean ? cleanBonus : 0)
    }
}

/// Daily amounts shown beside what was eaten. Protein, carbohydrate, and fat are the large rows.
public enum NutrientGuide {
    public static let headlines: [Nutrient] = [.protein, .carbohydrate, .fat]

    /// Returns the daily target of a nutrient.
    public static func daily(
        _ nutrient: Nutrient,
        weightKg: Double,
        sex: BodySex,
        goal: BodyGoal,
        calorieTarget: Int?
    ) -> Int {
        switch nutrient {
        case .calories:
            return calorieTarget ?? 0
        case .protein:
            let gramsPerKg = goal == .maintain ? 1.2 : 1.6
            return Int((max(weightKg, 0) * gramsPerKg).rounded())
        case .carbohydrate:
            return share(calorieTarget, percent: 45, perUnit: 4)
        case .fat:
            return share(calorieTarget, percent: 30, perUnit: 9)
        case .saturatedFat:
            return share(calorieTarget, percent: 10, perUnit: 9)
        case .fiber:
            return 30
        case .omega3:
            switch sex {
            case .male: return 2
            case .female: return 1
            case .unspecified: return 2
            }
        case .omega6:
            switch sex {
            case .male: return 17
            case .female: return 12
            case .unspecified: return 14
            }
        case .vitaminD:
            return 20
        case .vitaminB12:
            return 4
        case .vitaminC:
            switch sex {
            case .male: return 110
            case .female: return 95
            case .unspecified: return 100
            }
        case .calcium:
            return 1000
        case .iron:
            switch sex {
            case .male: return 10
            case .female: return 15
            case .unspecified: return 12
            }
        case .magnesium:
            switch sex {
            case .male: return 350
            case .female: return 300
            case .unspecified: return 325
            }
        }
    }

    /// Converts a calorie share into an amount.
    private static func share(_ calories: Int?, percent: Int, perUnit: Int) -> Int {
        guard let calories, calories > 0, perUnit > 0 else { return 0 }
        return Int((Double(calories) * Double(percent) / 100 / Double(perUnit)).rounded())
    }
}

/// Calculates daily targets and totals.
public enum NutritionPlan {
    /// Sedentary maintenance, because the profile does not ask for a job.
    public static let activityPercent = 120
    /// Added on a day that already has a finished workout.
    public static let trainingBonus = 250

    /// Parses a typed amount.
    public static func amount(from text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    /// Parses a day key.
    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map { calendar.startOfDay(for: $0) }
    }

    /// Builds a day key.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Returns the age on a day.
    public static func age(birth: Birthday, on day: Date, calendar: Calendar = .current) -> Int {
        guard let born = calendar.date(from: DateComponents(year: birth.year, month: birth.month, day: birth.day)) else {
            return 0
        }
        return max(calendar.dateComponents([.year], from: born, to: day).year ?? 0, 0)
    }

    /// Calculates resting calories.
    public static func restingCalories(weightKg: Double, heightCm: Double, age: Int, sex: BodySex) -> Int {
        let raw = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + sex.mifflinOffset
        return Int(raw.rounded())
    }

    /// Returns a rounded percentage.
    public static func percent(_ value: Int, _ percent: Int) -> Int {
        Int(((Double(value) * Double(percent)) / 100).rounded())
    }

    /// Nil until height and weight are set. A logged workout adds `trainingBonus` after the goal.
    public static func dayTarget(
        weightKg: Double,
        heightCm: Double,
        age: Int,
        sex: BodySex,
        goal: BodyGoal,
        trained: Bool
    ) -> Int? {
        guard weightKg > 0, heightCm > 0, age >= 0 else { return nil }
        let resting = restingCalories(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
        let maintenance = percent(resting, activityPercent)
        let aimed = max(percent(maintenance, goal.percent), sex.calorieFloor)
        return aimed + (trained ? trainingBonus : 0)
    }

    /// Returns a day's calorie target.
    public static func dayTarget(
        measures: BodyMeasures,
        birth: Birthday?,
        on day: Date,
        trained: Bool,
        calendar: Calendar = .current
    ) -> Int? {
        let years = birth.map { age(birth: $0, on: day, calendar: calendar) } ?? 30
        return dayTarget(
            weightKg: measures.weightKg,
            heightCm: measures.heightCm,
            age: years,
            sex: measures.sex,
            goal: measures.goal,
            trained: trained
        )
    }

    /// Says whether a session finished that day.
    public static func trained(on day: Date, sessions: [WorkoutSession], calendar: Calendar = .current) -> Bool {
        sessions.contains { calendar.isDate($0.finishedAt, inSameDayAs: day) }
    }

    /// Lists the meals of a day.
    public static func onDay(_ key: String, meals: [MealRecord]) -> [MealRecord] {
        meals.filter { $0.dayKey == key }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Sums a nutrient.
    public static func total(_ nutrient: Nutrient, meals: [MealRecord]) -> Double {
        meals.reduce(0) { $0 + $1.amount(nutrient) }
    }

    /// Sums and rounds a nutrient.
    public static func rounded(_ nutrient: Nutrient, meals: [MealRecord]) -> Int {
        Int(total(nutrient, meals: meals).rounded())
    }
}

/// Stores the meals.
@MainActor
public enum MealLog {
    private static var cached: [MealRecord]?

    /// Drops the in-memory copy.
    public static func clearCache() {
        cached = nil
    }

    /// Returns all meals.
    public static func all() -> [MealRecord] {
        if let cached { return cached }
        let meals = LififyDatabase.rows(FetchDescriptor<StoredMeal>()).map(\.meal).sorted { $0.createdAt < $1.createdAt }
        cached = meals
        return meals
    }

    /// Adds or updates a meal.
    public static func upsert(_ meal: MealRecord) {
        var meals = all()
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
        cached = meals.sorted { $0.createdAt < $1.createdAt }
        guard let context = LififyDatabase.sideContext else { return }
        let id = meal.id
        if let row = (try? context.fetch(FetchDescriptor<StoredMeal>(predicate: #Predicate { $0.mealID == id })))?.first {
            row.update(from: meal)
        } else {
            context.insert(StoredMeal(meal))
        }
        LififyDatabase.saveSide()
    }

    /// Deletes a meal.
    public static func remove(id: UUID) {
        cached = all().filter { $0.id != id }
        guard let context = LififyDatabase.sideContext else { return }
        ((try? context.fetch(FetchDescriptor<StoredMeal>(predicate: #Predicate { $0.mealID == id }))) ?? []).forEach(context.delete)
        LififyDatabase.saveSide()
    }

    /// Deletes all meals.
    public static func reset() {
        LififyDatabase.deleteAll(StoredMeal.self)
        cached = []
    }

    /// Exports the meals as JSON for a backup.
    public static func exportJSON() -> String {
        let meals = all()
        guard !meals.isEmpty, let data = try? JSONEncoder().encode(meals) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Replaces the meals from a backup.
    public static func restore(json: String) {
        reset()
        guard let data = json.data(using: .utf8),
              let meals = try? JSONDecoder().decode([MealRecord].self, from: data)
        else { return }
        if let context = LififyDatabase.sideContext {
            var unique: [UUID: MealRecord] = [:]
            meals.forEach { unique[$0.id] = $0 }
            unique.values.forEach { context.insert(StoredMeal($0)) }
            LififyDatabase.saveSide()
        }
        cached = nil
    }
}

/// Stores meal photos on the device.
public enum MealPhotoStore {
    /// Stores a photo and returns its name.
    public static func save(_ data: Data, id: UUID) -> String? {
        guard !data.isEmpty, data.count < 8_000_000 else { return nil }
        let name = "\(id.uuidString).jpg"
        let url = directory().appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// Loads a photo.
    public static func load(_ name: String) -> Data? {
        guard !name.isEmpty else { return nil }
        return try? Data(contentsOf: directory().appendingPathComponent(name))
    }

    /// Deletes a photo.
    public static func remove(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory().appendingPathComponent(name))
    }

    /// Deletes all photos.
    public static func removeAll() {
        try? FileManager.default.removeItem(at: directory())
    }

    /// The photo folder.
    private static func directory() -> URL {
        AppFiles.supportDirectory.appendingPathComponent("MealPhotos", isDirectory: true)
    }
}
