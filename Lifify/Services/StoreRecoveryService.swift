import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import Foundation
import SwiftData

/// Why a store recovery cannot start.
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

    /// Only an unfinished setup may move a broken store aside.
    nonisolated static func movesStoreAside(setupComplete: Bool) -> Bool {
        !setupComplete
    }

    private static var setupComplete: Bool {
        AppDefaults.store.bool(forKey: "hasCompletedOnboarding")
    }

    /// The database file in the app's own folder.
    ///
    /// The path is fixed on purpose. Without it SwiftData moves the store into the App Group as soon
    /// as the app has one, and the archive and recovery steps here would look in the wrong folder.
    static var storeURL: URL {
        AppFiles.supportDirectory.appendingPathComponent("default.store")
    }

    /// Opens the database with its upgrade path.
    static func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LififySchemaV4.self)
        let configuration = ModelConfiguration(schema: schema, url: url ?? storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: LififyMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Opens the database and handles a failure by setup state.
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

    /// Applies the store generation rule at launch.
    static func prepareCompatibleStore() {
        guard AppDefaults.store.integer(forKey: generationKey) != currentGeneration else { return }
        if movesStoreAside(setupComplete: setupComplete) {
            archiveExistingStores()
            resetLaunchState()
        }
        AppDefaults.store.set(currentGeneration, forKey: generationKey)
    }

    /// Archives the stores and restarts setup.
    static func archiveExistingStoresAndReset() {
        archiveExistingStores()
        resetLaunchState()
    }

    /// Resets the setup state.
    private static func resetLaunchState() {
        let defaults = AppDefaults.store
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "onboardingInProgress")
        defaults.set(0, forKey: "onboardingStep")
        IncomeAssignmentStore.reset()
    }

    /// Lists a folder's store files.
    private static func storeFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("default.store") || name.hasPrefix("LififyRecoveryV2.store")
        }
    }

    /// Moves the stores into a new archive folder.
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

    /// Deletes the current stores.
    private static func removeCurrentStores() {
        storeFiles(in: AppFiles.supportDirectory).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Moves archived stores back.
    private static func moveStores(from archive: URL) {
        let support = AppFiles.supportDirectory
        for source in storeFiles(in: archive) {
            try? FileManager.default.moveItem(at: source, to: support.appendingPathComponent(source.lastPathComponent))
        }
        try? FileManager.default.removeItem(at: archive)
    }
}
