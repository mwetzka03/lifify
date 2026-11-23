import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData

/// One finished one-time move of stored data. It is saved together with the moved rows.
@Model
final class DataMigrationRecord {
    @Attribute(.unique) var area: String
    var completedAt: Date

    init(area: String, completedAt: Date = .now) {
        self.area = area
        self.completedAt = completedAt
    }
}

enum LififySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            Account.self,
            LedgerEntry.self,
            TransactionSplit.self,
            FixedCost.self,
            VariableBudget.self,
            BudgetPool.self,
            IncomeForecast.self,
            ShoppingItem.self,
            DebtEntry.self,
            ExpenseGroup.self,
            ExpenseGroupLine.self,
            PortfolioHolding.self,
            SavedArticle.self
        ]
    }
}

enum LififySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        LififySchemaV1.models + [
            ChallengeCalendarEvent.self,
            LififySchemaV3.ChallengeItem.self,
            ChallengeCompletion.self,
            ChallengeGroup.self,
            CoinTransaction.self,
            RewardItem.self,
            RewardPurchase.self,
            BucketListItem.self
        ]
    }
}

enum LififySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        LififySchemaV2.models + [
            DataMigrationRecord.self,
            StoredHoldingLot.self,
            StoredSavingsPlan.self,
            StoredClosedPosition.self,
            StoredHoldingMarket.self,
            StoredPortfolioLink.self,
            StoredLink.self,
            StoredTransferForecast.self,
            StoredNoticeTemplate.self,
            StoredStreakState.self,
            StoredWorkoutLink.self,
            StoredMeal.self
        ]
    }

    /// The challenge as stored up to 0.5.5, frozen so those stores can still be opened.
    /// Versions 2 and 3 share it. `groupID` is the column that version 4 removes.
    @Model
    final class ChallengeItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var details: String
        var categoryRaw: String
        var recurrenceRaw: String
        var startDate: Date?
        var endDate: Date?
        var weeklyDays: String
        var rewardCoins: Int
        var streakTarget: Int
        var groupID: UUID?
        var groupIDsRaw: String = ""
        var isArchived: Bool
        var externalIdentifier: String?
        var isReadOnly: Bool
        var createdAt: Date

        /// Creates a stored challenge with the defaults of 0.5.5.
        init(id: UUID = UUID(), title: String, groupID: UUID? = nil, createdAt: Date = .now) {
            self.id = id
            self.title = title
            details = ""
            categoryRaw = ChallengeCategory.other.rawValue
            recurrenceRaw = ChallengeRecurrence.none.rawValue
            weeklyDays = ""
            rewardCoins = 10
            streakTarget = 0
            self.groupID = groupID
            groupIDsRaw = groupID?.uuidString ?? ""
            isArchived = false
            isReadOnly = false
            self.createdAt = createdAt
        }
    }
}

/// Version 4 removes the single-group column. `groupIDsRaw` holds all memberships.
enum LififySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        let frozen = ObjectIdentifier(LififySchemaV3.ChallengeItem.self)
        return LififySchemaV3.models.filter { ObjectIdentifier($0) != frozen } + [LififyCore.ChallengeItem.self]
    }
}

enum LififyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LififySchemaV1.self, LififySchemaV2.self, LififySchemaV3.self, LififySchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LififySchemaV1.self, toVersion: LififySchemaV2.self),
            .lightweight(fromVersion: LififySchemaV2.self, toVersion: LififySchemaV3.self),
            .custom(
                fromVersion: LififySchemaV3.self,
                toVersion: LififySchemaV4.self,
                willMigrate: { try keepSingleGroups(in: $0) },
                didMigrate: nil
            )
        ]
    }

    /// Copies a group that exists only in the old column, before that column is dropped.
    private static func keepSingleGroups(in context: ModelContext) throws {
        for challenge in try context.fetch(FetchDescriptor<LififySchemaV3.ChallengeItem>())
        where challenge.groupIDsRaw.isEmpty {
            if let group = challenge.groupID { challenge.groupIDsRaw = group.uuidString }
        }
        try context.save()
    }
}
