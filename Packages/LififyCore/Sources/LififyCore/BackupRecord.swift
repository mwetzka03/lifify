import Foundation

/// The content of a backup file.
public struct LififyBackup: Codable {
    public let version: Int
    public let exportedAt: Date
    public let records: [BackupRecord]

    public init(version: Int, exportedAt: Date, records: [BackupRecord]) {
        self.version = version
        self.exportedAt = exportedAt
        self.records = records
    }
}

/// One backed-up row in a generic form that older and newer versions can read.
public struct BackupRecord: Codable {
    public let type: String
    public let id: UUID
    public var strings: [String] = []
    public var integers: [Int] = []
    public var doubles: [Double] = []
    public var booleans: [Bool] = []
    public var dates: [Date?] = []
    public var uuids: [UUID?] = []

    public init(
        type: String,
        id: UUID,
        strings: [String] = [],
        integers: [Int] = [],
        doubles: [Double] = [],
        booleans: [Bool] = [],
        dates: [Date?] = [],
        uuids: [UUID?] = []
    ) {
        self.type = type
        self.id = id
        self.strings = strings
        self.integers = integers
        self.doubles = doubles
        self.booleans = booleans
        self.dates = dates
        self.uuids = uuids
    }

    /// Decodes a record. Fields missing from older backups fall back to empty values.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decode(UUID.self, forKey: .id)
        strings = try container.decodeIfPresent([String].self, forKey: .strings) ?? []
        integers = try container.decodeIfPresent([Int].self, forKey: .integers) ?? []
        doubles = try container.decodeIfPresent([Double].self, forKey: .doubles) ?? []
        booleans = try container.decodeIfPresent([Bool].self, forKey: .booleans) ?? []
        dates = try container.decodeIfPresent([Date?].self, forKey: .dates) ?? []
        uuids = try container.decodeIfPresent([UUID?].self, forKey: .uuids) ?? []
    }
}
