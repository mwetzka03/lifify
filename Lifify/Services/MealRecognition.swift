import Foundation
import Security
import UIKit

enum KeychainStore {
    static let nutritionService = "lifify.nutrition"
    /// Session cookie for a manual Trade Republic sign-in. Not the nutrition key.
    static let tradeRepublicService = "lifify.traderepublic"
    static let tradeRepublicAccount = "session"
    /// This device only, so the item is left out of backups. Same rule as the Gemini key.
    static let deviceOnly = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func set(_ value: String, account: String, service: String = nutritionService) {
        remove(account: account, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: deviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func string(account: String, service: String = nutritionService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func remove(account: String, service: String = nutritionService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct MealPerson: Equatable {
    var heightCm: Double
    var weightKg: Double
    var age: Int
    var sex: String
    var goal: String
    var trained: Bool
}

struct MealReading: Equatable {
    var title: String
    var kind: MealKind
    var note: String
    var nutrients: [String: Double]
}

extension MealRecognition {
    /// Sends one photo to Gemini when a key is stored. Returns nil when the key is missing or the answer cannot be read.
    static func read(image: Data, person: MealPerson, correction: String) async -> MealReading? {
        guard let key = KeychainStore.string(account: keyAccount)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let jpeg = MealPhotoFit.jpeg(image)
        else { return nil }
        let prompt = prompt(person: person, correction: correction)
        if let reading = await send(prompt: prompt, jpeg: jpeg, key: key, thinking: true) {
            return reading
        }
        return await send(prompt: prompt, jpeg: jpeg, key: key, thinking: false)
    }

    private static func send(prompt: String, jpeg: Data, key: String, thinking: Bool) async -> MealReading? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var generation: [String: Any] = [
            "temperature": 0.2,
            "responseMimeType": "application/json"
        ]
        if thinking {
            generation["thinkingConfig"] = ["thinkingBudget": 0]
        }
        let payload: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
                ]
            ]],
            "generationConfig": generation
        ]
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = encoded
        guard let (bytes, raw) = try? await URLSession.shared.data(for: request),
              let http = raw as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return nil }
        return parse(bytes)
    }

    private static func prompt(person: MealPerson, correction: String) -> String {
        let kinds = MealKind.allCases.map(\.rawValue).joined(separator: "|")
        let nutrients = Nutrient.allCases.map(\.rawValue).joined(separator: ", ")
        var lines = [
            "Estimate the one meal in the photo. Reply with one JSON object and no other text.",
            "Fields: title, kind, note, and one number for each of \(nutrients).",
            "kind is one of \(kinds).",
            "whole: vegetables, fruit, plain fish, eggs, legumes, whole grains, little added fat.",
            "balanced: a mixed plate with protein, starch, and vegetables.",
            "hearty: creamy, fried, cheese-heavy, or a large fatty home meal.",
            "sweet: cake, ice cream, candy, or a sweet pastry.",
            "fastFood: burger, fries, fried chicken, pizza delivery, doner, or nuggets.",
            "alcohol: beer, wine, or spirits.",
            "Calories are kcal. Vitamin D and vitamin B12 are µg. Vitamin C, calcium, iron, and magnesium are mg. The rest are grams. Use the portion visible in the photo.",
            "Person: \(Int(person.heightCm)) cm, \(Int(person.weightKg)) kg, age \(person.age), sex \(person.sex), goal \(person.goal), workout today \(person.trained ? "yes" : "no").",
            "title and note use the person's language when the correction is German, otherwise English."
        ]
        let trimmed = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("The person corrected the first reading. Trust this correction: \(trimmed)")
        }
        return lines.joined(separator: "\n")
    }

    private static func parse(_ data: Data) -> MealReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return nil }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = cleaned.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        let source = (object["nutrients"] as? [String: Any]) ?? object
        var nutrients: [String: Double] = [:]
        for nutrient in Nutrient.allCases {
            if let number = Self.number(source[nutrient.rawValue]) {
                nutrients[nutrient.rawValue] = max(number, 0)
            }
        }
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let note = (object["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = MealKind.resolved((object["kind"] as? String) ?? "")
        return MealReading(title: title.isEmpty ? L("Mahlzeit", "Meal") : title, kind: kind, note: note, nutrients: nutrients)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}

enum MealPhotoFit {
    static func jpeg(_ data: Data, maxEdge: CGFloat = 768) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let drawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return drawn.jpegData(compressionQuality: 0.72)
    }
}
