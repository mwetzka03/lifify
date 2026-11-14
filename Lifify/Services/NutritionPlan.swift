import Foundation

/// Sex used by the calorie estimate. Unspecified uses the midpoint of the two formulas.
enum BodySex: String, CaseIterable, Identifiable {
    case female
    case male
    case unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .female: L("Weiblich", "Female")
        case .male: L("Männlich", "Male")
        case .unspecified: L("Keine Angabe", "Unspecified")
        }
    }

    /// Mifflin–St Jeor constant. Unspecified is the midpoint of +5 and −161.
    var mifflinOffset: Double {
        switch self {
        case .male: 5
        case .female: -161
        case .unspecified: -78
        }
    }

    var calorieFloor: Int {
        switch self {
        case .female: 1200
        case .male: 1500
        case .unspecified: 1350
        }
    }

    static func resolved(_ raw: String) -> BodySex {
        BodySex(rawValue: raw) ?? .unspecified
    }
}

/// What the calorie target is aiming at.
enum BodyGoal: String, CaseIterable, Identifiable {
    case loseFat
    case maintain
    case gainMuscle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loseFat: L("Fett verlieren", "Lose fat")
        case .maintain: L("Halten", "Maintain")
        case .gainMuscle: L("Muskeln aufbauen", "Build muscle")
        }
    }

    /// Percent of the sedentary maintenance. 85 loses fat, 100 holds, 110 builds muscle.
    var percent: Int {
        switch self {
        case .loseFat: 85
        case .maintain: 100
        case .gainMuscle: 110
        }
    }

    static func resolved(_ raw: String) -> BodyGoal {
        BodyGoal(rawValue: raw) ?? .maintain
    }
}

struct BodyMeasures: Equatable {
    var heightCm: Double
    var weightKg: Double
    var sex: BodySex
    var goal: BodyGoal

    var isComplete: Bool { heightCm > 0 && weightKg > 0 }

    static let empty = BodyMeasures(heightCm: 0, weightKg: 0, sex: .unspecified, goal: .maintain)
}

enum UserBody {
    static let heightKey = "lifify.userHeightCm"
    static let weightKey = "lifify.userWeightKg"
    static let sexKey = "lifify.userSex"
    static let goalKey = "lifify.userGoal"

    static func current(defaults: UserDefaults = .standard) -> BodyMeasures {
        BodyMeasures(
            heightCm: defaults.double(forKey: heightKey),
            weightKg: defaults.double(forKey: weightKey),
            sex: BodySex.resolved(defaults.string(forKey: sexKey) ?? ""),
            goal: BodyGoal.resolved(defaults.string(forKey: goalKey) ?? "")
        )
    }

    static func heightText(defaults: UserDefaults = .standard) -> String {
        text(current(defaults: defaults).heightCm)
    }

    static func weightText(defaults: UserDefaults = .standard) -> String {
        text(current(defaults: defaults).weightKg)
    }

    static func save(
        heightText: String,
        weightText: String,
        sex: BodySex,
        goal: BodyGoal,
        defaults: UserDefaults = .standard
    ) {
        store(NutritionPlan.amount(from: heightText), key: heightKey, defaults: defaults)
        store(NutritionPlan.amount(from: weightText), key: weightKey, defaults: defaults)
        defaults.set(sex.rawValue, forKey: sexKey)
        defaults.set(goal.rawValue, forKey: goalKey)
    }

    static func restore(height: String, weight: String, sex: String, goal: String, defaults: UserDefaults = .standard) {
        save(
            heightText: height,
            weightText: weight,
            sex: BodySex.resolved(sex),
            goal: BodyGoal.resolved(goal),
            defaults: defaults
        )
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: heightKey)
        defaults.removeObject(forKey: weightKey)
        defaults.removeObject(forKey: sexKey)
        defaults.removeObject(forKey: goalKey)
    }

    private static func store(_ value: Double, key: String, defaults: UserDefaults) {
        if value > 0 {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func text(_ value: Double) -> String {
        guard value > 0 else { return "" }
        let shown = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        if UserDefaults.standard.string(forKey: "appLanguage") == "en" { return shown }
        return shown.replacingOccurrences(of: ".", with: ",")
    }
}

enum Nutrient: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

    var isPrimary: Bool {
        switch self {
        case .calories, .protein, .carbohydrate, .fat, .saturatedFat, .omega3, .omega6, .fiber: true
        default: false
        }
    }

    var unit: String {
        switch self {
        case .calories: "kcal"
        case .vitaminD, .vitaminB12: "µg"
        case .calcium, .iron, .magnesium, .vitaminC: "mg"
        default: "g"
        }
    }

    var label: String {
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
enum MealKind: String, Codable, CaseIterable, Identifiable {
    case whole
    case balanced
    case hearty
    case sweet
    case fastFood
    case alcohol

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whole: L("Unverarbeitet", "Whole food")
        case .balanced: L("Ausgewogen", "Balanced")
        case .hearty: L("Deftig", "Hearty")
        case .sweet: L("Süß", "Sweet")
        case .fastFood: L("Fast Food", "Fast food")
        case .alcohol: L("Alkohol", "Alcohol")
        }
    }

    static func resolved(_ raw: String) -> MealKind {
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

enum MealSource: String, Codable {
    case manual
    case photo
}

enum MealStatus: String, Codable {
    case draft
    case confirmed
}

struct MealRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var dayKey: String
    var title: String
    var note: String
    var correction: String
    var createdAt: Date
    var source: MealSource
    var status: MealStatus
    var photoName: String?
    var nutrients: [String: Double]
    var kindRaw: String
    var chargeID: UUID?

    var kind: MealKind {
        get { MealKind.resolved(kindRaw) }
        set { kindRaw = newValue.rawValue }
    }

    init(
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

    func amount(_ nutrient: Nutrient) -> Double {
        nutrients[nutrient.rawValue] ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, dayKey, title, note, correction, createdAt, source, status, photoName, nutrients, kindRaw, chargeID
    }

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

enum NutritionCopy {
    static var recognitionPending: String {
        L("Die Erkennung ist noch nicht verbunden.", "Recognition is not connected yet.")
    }

    static var recognitionFailed: String {
        L("Die Erkennung hat nicht geantwortet. Die Werte kannst du selbst setzen.", "Recognition did not answer. You can set the values yourself.")
    }

    static var recognizing: String {
        L("Das Foto wird gelesen.", "The photo is being read.")
    }

    static var emptyDay: String {
        L("Noch keine Mahlzeit an diesem Tag.", "No meal on this day yet.")
    }

    static var calorieChallenge: String {
        challengeTitle(for: .loseFat)
    }

    static func challengeTitle(for goal: BodyGoal) -> String {
        switch goal {
        case .loseFat: L("Kaloriendefizit", "Calorie deficit")
        case .maintain: L("Kalorien halten", "Hold calories")
        case .gainMuscle: L("Muskelaufbau", "Build muscle")
        }
    }

    static let previousCalorieTitles = ["Unter dem Kalorienziel", "Under the calorie target"]

    static var automaticTitles: [String] {
        previousCalorieTitles + [
            "Kaloriendefizit", "Calorie deficit",
            "Kalorien halten", "Hold calories",
            "Muskelaufbau", "Build muscle"
        ]
    }
}

/// A camera shot is kept in the app. It reaches the photo library only when this is on.
enum MealCapture {
    static let saveKey = "lifify.saveMealPhotos"

    static func keepsInLibrary(_ enabled: Bool) -> Bool { enabled }
}

/// Photo recognition follows the Gemini key stored under Health. See ERNAEHRUNG.md.
enum MealRecognition {
    static let keyAccount = "gemini.api.key"
    static let model = "gemini-2.5-flash"

    static var isConnected: Bool {
        connected(hasKey: !(KeychainStore.string(account: keyAccount) ?? "").isEmpty)
    }

    static func connected(hasKey: Bool) -> Bool { hasKey }
}

/// Coins for a day at or under the calorie target, and the shop price of fast food.
enum MealScore {
    static let baseCoins = 20
    static let cleanBonus = 10
    static let fastFoodPrice = 25

    static func points(for kind: MealKind) -> Int {
        switch kind {
        case .whole: 2
        case .balanced: 1
        case .hearty: 0
        case .sweet: -1
        case .alcohol: -1
        case .fastFood: -2
        }
    }

    static func buysFastFood(_ kinds: [MealKind]) -> Bool {
        kinds.contains(.fastFood)
    }

    /// Lose fat stays at or under the target. Build muscle has to reach it.
    /// Maintain stays inside 90 to 110 percent. An empty day never qualifies.
    static func qualifies(eaten: Int, target: Int?, goal: BodyGoal) -> Bool {
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
    static func balance(afterRemoving awarded: Int, from balance: Int) -> Int {
        balance - awarded
    }

    /// Zero when the day misses the goal. A day of only whole and balanced meals adds the clean bonus.
    static func coins(eaten: Int, target: Int?, kinds: [MealKind], goal: BodyGoal = .loseFat) -> Int {
        guard qualifies(eaten: eaten, target: target, goal: goal) else { return 0 }
        let clean = !kinds.isEmpty && kinds.allSatisfy { points(for: $0) > 0 }
        return baseCoins + (clean ? cleanBonus : 0)
    }
}

/// Daily amounts shown beside what was eaten. Protein, carbohydrate, and fat are the large rows.
enum NutrientGuide {
    static let headlines: [Nutrient] = [.protein, .carbohydrate, .fat]

    static func daily(
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

    private static func share(_ calories: Int?, percent: Int, perUnit: Int) -> Int {
        guard let calories, calories > 0, perUnit > 0 else { return 0 }
        return Int((Double(calories) * Double(percent) / 100 / Double(perUnit)).rounded())
    }
}

enum NutritionPlan {
    /// Sedentary maintenance, because the profile does not ask for a job.
    static let activityPercent = 120
    /// Added on a day that already has a finished workout.
    static let trainingBonus = 250

    static func amount(from text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map { calendar.startOfDay(for: $0) }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func age(birth: Birthday, on day: Date, calendar: Calendar = .current) -> Int {
        guard let born = calendar.date(from: DateComponents(year: birth.year, month: birth.month, day: birth.day)) else {
            return 0
        }
        return max(calendar.dateComponents([.year], from: born, to: day).year ?? 0, 0)
    }

    static func restingCalories(weightKg: Double, heightCm: Double, age: Int, sex: BodySex) -> Int {
        let raw = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age)) + sex.mifflinOffset
        return Int(raw.rounded())
    }

    static func percent(_ value: Int, _ percent: Int) -> Int {
        Int(((Double(value) * Double(percent)) / 100).rounded())
    }

    /// Nil until height and weight are set. A logged workout adds `trainingBonus` after the goal.
    static func dayTarget(
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

    static func dayTarget(
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

    static func trained(on day: Date, sessions: [WorkoutSession], calendar: Calendar = .current) -> Bool {
        sessions.contains { calendar.isDate($0.finishedAt, inSameDayAs: day) }
    }

    static func onDay(_ key: String, meals: [MealRecord]) -> [MealRecord] {
        meals.filter { $0.dayKey == key }.sorted { $0.createdAt < $1.createdAt }
    }

    static func total(_ nutrient: Nutrient, meals: [MealRecord]) -> Double {
        meals.reduce(0) { $0 + $1.amount(nutrient) }
    }

    static func rounded(_ nutrient: Nutrient, meals: [MealRecord]) -> Int {
        Int(total(nutrient, meals: meals).rounded())
    }
}

@MainActor
enum MealLog {
    private static let key = "lifify.meals"

    static func all(defaults: UserDefaults = .standard) -> [MealRecord] {
        guard let data = defaults.data(forKey: key),
              let meals = try? JSONDecoder().decode([MealRecord].self, from: data)
        else { return [] }
        return meals.sorted { $0.createdAt < $1.createdAt }
    }

    static func upsert(_ meal: MealRecord, defaults: UserDefaults = .standard) {
        var meals = all(defaults: defaults)
        if let index = meals.firstIndex(where: { $0.id == meal.id }) {
            meals[index] = meal
        } else {
            meals.append(meal)
        }
        save(meals, defaults: defaults)
    }

    static func remove(id: UUID, defaults: UserDefaults = .standard) {
        save(all(defaults: defaults).filter { $0.id != id }, defaults: defaults)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    static func exportJSON(defaults: UserDefaults = .standard) -> String {
        let meals = all(defaults: defaults)
        guard !meals.isEmpty, let data = try? JSONEncoder().encode(meals) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func restore(json: String, defaults: UserDefaults = .standard) {
        guard let data = json.data(using: .utf8),
              let meals = try? JSONDecoder().decode([MealRecord].self, from: data)
        else {
            reset(defaults: defaults)
            return
        }
        save(meals, defaults: defaults)
    }

    private static func save(_ meals: [MealRecord], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        defaults.set(data, forKey: key)
    }
}

enum MealPhotoStore {
    static func save(_ data: Data, id: UUID) -> String? {
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

    static func load(_ name: String) -> Data? {
        guard !name.isEmpty else { return nil }
        return try? Data(contentsOf: directory().appendingPathComponent(name))
    }

    static func remove(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory().appendingPathComponent(name))
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MealPhotos", isDirectory: true)
    }
}
