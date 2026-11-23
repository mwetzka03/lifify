import Foundation
import SwiftData

/// The app's container, plus a separate context for stores that have no view-level context.
/// Its saves never commit a form the person is still editing on the main context.
@MainActor
public enum LififyDatabase {
    public static var container: ModelContainer? {
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

    public private(set) static var sideContext: ModelContext?

    /// Fetches rows from the side context. Returns nothing before the store is open.
    public static func rows<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        guard let sideContext else { return [] }
        return (try? sideContext.fetch(descriptor)) ?? []
    }

    /// Deletes all rows of a type from the side context.
    public static func deleteAll<T: PersistentModel>(_ type: T.Type) {
        guard let sideContext else { return }
        rows(FetchDescriptor<T>()).forEach(sideContext.delete)
        saveSide()
    }

    /// Saves the side context.
    public static func saveSide() {
        guard let sideContext else { return }
        do {
            try sideContext.save()
        } catch {
            assertionFailure("Saving Lifify data failed: \(error)")
            sideContext.rollback()
        }
    }
}
