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
        nutrients: [String: Double] = [:]
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
    }

    func amount(_ nutrient: Nutrient) -> Double {
        nutrients[nutrient.rawValue] ?? 0
    }
}

enum NutritionCopy {
    static var recognitionPending: String {
        L("Die Erkennung ist noch nicht verbunden.", "Recognition is not connected yet.")
    }

    static var emptyDay: String {
        L("Noch keine Mahlzeit an diesem Tag.", "No meal on this day yet.")
    }

    static var estimateNote: String {
        L("Schätzung, keine medizinische Beratung.", "An estimate, not medical advice.")
    }
}

/// Photo recognition stays off until an API key is connected. See ERNAEHRUNG.md.
enum MealRecognition {
    static let isConnected = false
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
