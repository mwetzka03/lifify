import SwiftData

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
            LifeCalendarEvent.self,
            LifeChallenge.self,
            ChallengeCompletion.self,
            LifeChallengeGroup.self,
            CoinTransaction.self,
            RewardItem.self,
            RewardPurchase.self,
            BucketListItem.self,
            VisionBoard.self,
            VisionBoardElement.self
        ]
    }
}

enum LififyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LififySchemaV1.self, LififySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: LififySchemaV1.self, toVersion: LififySchemaV2.self)
        ]
    }
}
