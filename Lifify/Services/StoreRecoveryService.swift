import Foundation
import SwiftData

enum StoreRecoveryError: LocalizedError {
    case notAFullBackup

    var errorDescription: String? {
        L(
            "Zum Wiederherstellen wird eine Sicherung der gesamten App gebraucht.",
            "Recovery needs a backup of the entire app."
        )
    }
}

/// Opens the database. During first-time setup a broken store is moved aside and setup starts again.
/// A finished app never loses its store silently. It reports the error and offers a backup restore.
@MainActor
enum StoreRecoveryService {
    private static let generationKey = "lififyStoreGeneration"
    private static let currentGeneration = 3

    nonisolated static func movesStoreAside(setupComplete: Bool) -> Bool {
        !setupComplete
    }

    private static var setupComplete: Bool {
        AppDefaults.store.bool(forKey: "hasCompletedOnboarding")
    }

    static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LififySchemaV3.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(
            for: schema,
            migrationPlan: LififyMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func openContainer(url: URL? = nil) -> Result<ModelContainer, Error> {
        prepareCompatibleStore()
        do {
            return .success(try makeContainer(url: url))
        } catch let initialError {
            guard movesStoreAside(setupComplete: setupComplete) else { return .failure(initialError) }
            archiveExistingStoresAndReset()
            do {
                return .success(try makeContainer(url: url))
            } catch {
                return .failure(NSError(
                    domain: "com.mwetzka03.lifify.storage",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription) (\(initialError.localizedDescription))"
                    ]
                ))
            }
        }
    }

    /// The person chose this restore. The broken store is kept in an archive folder.
    /// When the restore fails, that store is put back.
    static func recover(from backup: Data, url: URL? = nil) throws -> ModelContainer {
        guard try BackupService.scope(ofData: backup) == .all else { throw StoreRecoveryError.notAFullBackup }
        let previous = LififyDatabase.container
        LififyDatabase.container = nil
        let archive = archiveExistingStores()
        do {
            let container = try makeContainer(url: url)
            LififyDatabase.container = container
            LegacyDataMigration.run()
            try BackupService.restore(data: backup, into: container.mainContext)
            try container.mainContext.save()
            return container
        } catch {
            LififyDatabase.container = previous
            removeCurrentStores()
            if let archive { moveStores(from: archive) }
            throw error
        }
    }

    static func prepareCompatibleStore() {
        guard AppDefaults.store.integer(forKey: generationKey) != currentGeneration else { return }
        if movesStoreAside(setupComplete: setupComplete) {
            archiveExistingStores()
            resetLaunchState()
        }
        AppDefaults.store.set(currentGeneration, forKey: generationKey)
    }

    static func archiveExistingStoresAndReset() {
        archiveExistingStores()
        resetLaunchState()
    }

    private static func resetLaunchState() {
        let defaults = AppDefaults.store
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "onboardingInProgress")
        defaults.set(0, forKey: "onboardingStep")
        IncomeAssignmentStore.reset()
    }

    private static func storeFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("default.store") || name.hasPrefix("LififyRecoveryV2.store")
        }
    }

    @discardableResult
    private static func archiveExistingStores() -> URL? {
        let fileManager = FileManager.default
        let support = AppFiles.supportDirectory
        let sources = storeFiles(in: support)
        guard !sources.isEmpty else { return nil }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let archive = support.appendingPathComponent("LififyStoreArchive-\(stamp)-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        for source in sources {
            let destination = archive.appendingPathComponent(source.lastPathComponent)
            try? fileManager.moveItem(at: source, to: destination)
        }
        return archive
    }

    private static func removeCurrentStores() {
        storeFiles(in: AppFiles.supportDirectory).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private static func moveStores(from archive: URL) {
        let support = AppFiles.supportDirectory
        for source in storeFiles(in: archive) {
            try? FileManager.default.moveItem(at: source, to: support.appendingPathComponent(source.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: archive)
    }
}
