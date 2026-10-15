import Foundation

enum DashboardPeriodMode: String, CaseIterable, Identifiable {
    case calendarMonth
    case salaryPeriod

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendarMonth: L("Kalendermonat", "Calendar month")
        case .salaryPeriod: L("Seit letztem Gehalt", "Since last salary")
        }
    }
}

enum IncomeAssignmentStore {
    static func setPrimary(iban: String, forecastID: UUID) {
        let normalized = normalize(iban)
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: "primaryIncomeIBAN")
        } else {
            UserDefaults.standard.set(normalized, forKey: "primaryIncomeIBAN")
        }
        UserDefaults.standard.set(forecastID.uuidString, forKey: "primaryIncomeForecastID")
    }

    static func setSecondary(_ values: [(iban: String, forecastID: UUID)]) {
        let pairs = values.compactMap { value -> (String, String)? in
            let iban = normalize(value.iban)
            return iban.isEmpty ? nil : (iban, value.forecastID.uuidString)
        }
        let mapping = Dictionary(pairs, uniquingKeysWith: { _, newest in newest })
        UserDefaults.standard.set(mapping, forKey: "secondaryIncomeMappings")
    }

    static func forecastID(for iban: String) -> UUID? {
        let normalized = normalize(iban)
        guard !normalized.isEmpty else { return nil }
        if UserDefaults.standard.string(forKey: "primaryIncomeIBAN") == normalized,
           let value = UserDefaults.standard.string(forKey: "primaryIncomeForecastID") {
            return UUID(uuidString: value)
        }
        let mapping = UserDefaults.standard.dictionary(forKey: "secondaryIncomeMappings") as? [String: String]
        return mapping?[normalized].flatMap(UUID.init(uuidString:))
    }

    static func assign(entryID: UUID, to forecastID: UUID) {
        var mapping = UserDefaults.standard.dictionary(forKey: "incomeEntryAssignments") as? [String: String] ?? [:]
        mapping[entryID.uuidString] = forecastID.uuidString
        UserDefaults.standard.set(mapping, forKey: "incomeEntryAssignments")
    }

    static func ibans(for forecastID: UUID) -> [String] {
        var values: [String] = []
        if UserDefaults.standard.string(forKey: "primaryIncomeForecastID") == forecastID.uuidString,
           let iban = UserDefaults.standard.string(forKey: "primaryIncomeIBAN") {
            let normalized = normalize(iban)
            if !normalized.isEmpty { values.append(normalized) }
        }
        let mapping = UserDefaults.standard.dictionary(forKey: "secondaryIncomeMappings") as? [String: String] ?? [:]
        for (iban, identifier) in mapping where identifier == forecastID.uuidString {
            let normalized = normalize(iban)
            if !normalized.isEmpty, !values.contains(normalized) { values.append(normalized) }
        }
        return values
    }

    static func forecastID(forEntryID entryID: UUID) -> UUID? {
        let mapping = UserDefaults.standard.dictionary(forKey: "incomeEntryAssignments") as? [String: String]
        return mapping?[entryID.uuidString].flatMap(UUID.init(uuidString:))
    }

    static func reset() {
        ["primaryIncomeIBAN", "primaryIncomeForecastID", "secondaryIncomeMappings", "incomeEntryAssignments"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    private static func normalize(_ iban: String) -> String {
        iban.replacingOccurrences(of: " ", with: "").uppercased()
    }
}

enum RewardPolicyStore {
    static func allowsMultiplePurchases(for rewardID: UUID) -> Bool {
        let key = key(for: rewardID)
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setAllowsMultiplePurchases(_ allowed: Bool, for rewardID: UUID) {
        UserDefaults.standard.set(allowed, forKey: key(for: rewardID))
    }

    static func remove(for rewardID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: rewardID))
    }

    private static func key(for rewardID: UUID) -> String {
        "reward.multiple.\(rewardID.uuidString)"
    }
}
