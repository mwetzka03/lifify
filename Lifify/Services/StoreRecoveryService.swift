import Foundation

enum StoreRecoveryService {
    private static let generationKey = "lififyStoreGeneration"
    private static let currentGeneration = 3

    static func prepareCompatibleStore() {
        guard UserDefaults.standard.integer(forKey: generationKey) != currentGeneration else { return }
        archiveExistingStores()
        resetLaunchState()
        UserDefaults.standard.set(currentGeneration, forKey: generationKey)
    }

    static func archiveExistingStoresAndReset() {
        archiveExistingStores()
        resetLaunchState()
    }

    private static func resetLaunchState() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "onboardingInProgress")
        defaults.set(0, forKey: "onboardingStep")
        IncomeAssignmentStore.reset()
    }

    private static func archiveExistingStores() {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let contents = try? fileManager.contentsOfDirectory(
                at: support,
                includingPropertiesForKeys: nil
              )
        else { return }

        let sources = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("default.store") || name.hasPrefix("LififyRecoveryV2.store")
        }
        guard !sources.isEmpty else { return }

        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let archive = support.appendingPathComponent("LififyStoreArchive-\(stamp)", isDirectory: true)
        try? fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        for source in sources {
            let destination = archive.appendingPathComponent(source.lastPathComponent)
            try? fileManager.moveItem(at: source, to: destination)
        }
    }
}
