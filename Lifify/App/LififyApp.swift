import SwiftData
import SwiftUI
import UserNotifications

@main
struct LififyApp: App {
    @State private var containerResult: Result<ModelContainer, Error>

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        AppClock.resetSimulatedDay()
        let result = StoreRecoveryService.openContainer()
        _containerResult = State(initialValue: result)
        if case .success(let container) = result {
            LififyDatabase.container = container
            LegacyDataMigration.run()
        }
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                AppEntryView()
                    .modelContainer(container)
            case .failure(let error):
                StoreFailureView(error: error) { container in
                    LififyDatabase.container = container
                    containerResult = .success(container)
                }
            }
        }
    }
}

/// The app's container, plus a separate context for stores that have no view-level context.
/// Its saves never commit a form the person is still editing on the main context.
@MainActor
enum LififyDatabase {
    static var container: ModelContainer? {
        didSet {
            ModelChangeCounter.startObserving()
            ModelChangeCounter.bump()
            sideContext = container.map { container in
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return context
            }
            AppDefaults.clearCaches()
        }
    }

    private(set) static var sideContext: ModelContext?

    static func rows<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        guard let sideContext else { return [] }
        return (try? sideContext.fetch(descriptor)) ?? []
    }

    static func deleteAll<T: PersistentModel>(_ type: T.Type) {
        guard let sideContext else { return }
        rows(FetchDescriptor<T>()).forEach(sideContext.delete)
        saveSide()
    }

    static func saveSide() {
        guard let sideContext else { return }
        do {
            try sideContext.save()
        } catch {
            assertionFailure("Saving Lifify data failed: \(error)")
            sideContext.rollback()
        }
    }
}
