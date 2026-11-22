import Foundation
import SwiftData

/// The one place services get their UserDefaults from.
/// The app always uses `.standard`. Tests swap in an isolated suite, so they never touch user data.
public enum AppDefaults {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replacement: UserDefaults?

    public static var store: UserDefaults {
        lock.lock()
        defer { lock.unlock() }
        return replacement ?? .standard
    }

    /// Switches the store and drops every in-memory copy of the previous store's values.
    /// Pass `nil` to return to `.standard`.
    @MainActor
    public static func use(_ store: UserDefaults?) {
        lock.lock()
        replacement = store
        lock.unlock()
        clearCaches()
    }

    @MainActor private static var cacheClearers: [@MainActor () -> Void] = []

    /// Each area adds the in-memory copies it keeps.
    @MainActor
    public static func registerCaches(_ clear: @escaping @MainActor () -> Void) {
        cacheClearers.append(clear)
    }

    @MainActor
    public static func clearCaches() {
        LinkTable.clearCache()
        cacheClearers.forEach { $0() }
    }
}

/// The folder for data files. Tests swap in a temporary one, so they never touch user files.
public enum AppFiles {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replacement: URL?

    public static var supportDirectory: URL {
        lock.lock()
        defer { lock.unlock() }
        return replacement ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    public static func use(_ directory: URL?) {
        lock.lock()
        replacement = directory
        lock.unlock()
    }
}

/// Counts saves across all model contexts, so derived values know when to recompute.
public enum ModelChangeCounter {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var observer: NSObjectProtocol?

    public static var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    public static func bump() {
        lock.lock()
        count &+= 1
        lock.unlock()
    }

    public static func startObserving() {
        lock.lock()
        let needsObserver = observer == nil
        lock.unlock()
        guard needsObserver else { return }
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            ModelChangeCounter.bump()
        }
        lock.lock()
        observer = token
        lock.unlock()
    }
}
