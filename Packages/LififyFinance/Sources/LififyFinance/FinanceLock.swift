import Foundation
import LififyCore
import LocalAuthentication
import Observation

/// Confirms the device owner, so tests can replace the real Face ID prompt.
public protocol DeviceAuthenticator: Sendable {
    /// Says whether a prompt can work. A device without a passcode has no way to confirm anyone.
    func canAuthenticate() -> Bool
    /// Asks for Face ID with the device passcode as fallback.
    func authenticate(reason: String) async -> Bool
}

/// The real authenticator, based on LocalAuthentication.
public struct LocalDeviceAuthenticator: DeviceAuthenticator {
    /// Creates the authenticator.
    public init() {}

    /// Only a missing device passcode makes the lock impossible.
    public func canAuthenticate() -> Bool {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return true }
        return error?.code != LAError.passcodeNotSet.rawValue
    }

    /// Shows the system prompt and reports whether it succeeded.
    public func authenticate(reason: String) async -> Bool {
        await withCheckedContinuation { continuation in
            LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

/// The stored choices of the finance lock. They stay out of backups, so a restore can never
/// turn the lock off on a device.
public enum FinanceLockSettings {
    public static let enabledKey = "lifify.financeLockEnabled"
    public static let widgetValuesKey = "lifify.financeWidgetValues"

    /// Whether Finance needs unlocking. On by default.
    public static var isEnabled: Bool {
        AppDefaults.store.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Whether finance widgets may show amounts while the lock is on. Off by default.
    public static var showsWidgetValues: Bool {
        AppDefaults.store.bool(forKey: widgetValuesKey)
    }

    /// Whether a finance widget may show its amounts right now.
    public static var widgetsMayShowAmounts: Bool {
        !isEnabled || showsWidgetValues
    }
}

/// Keeps Finance locked until the device owner confirms, and locks again in the background.
@MainActor
@Observable
public final class FinanceLock {
    public private(set) var isUnlocked = false
    public private(set) var isAuthenticating = false
    public private(set) var didFail = false
    @ObservationIgnored private let authenticator: any DeviceAuthenticator
    @ObservationIgnored private var generation = 0

    /// Creates a locked lock.
    public init(authenticator: any DeviceAuthenticator = LocalDeviceAuthenticator()) {
        self.authenticator = authenticator
    }

    /// Asks the owner to unlock. A result that arrives after the app left the foreground is ignored.
    public func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        guard authenticator.canAuthenticate() else {
            isUnlocked = true
            return
        }
        let started = generation
        isAuthenticating = true
        let success = await authenticator.authenticate(reason: Self.unlockReason)
        isAuthenticating = false
        guard started == generation else { return }
        isUnlocked = success
        didFail = !success
    }

    /// Locks Finance when the app goes to the background.
    public func lock() {
        generation += 1
        isUnlocked = false
        didFail = false
    }

    /// Allows the automatic prompt again after a cancelled attempt.
    public func allowPrompt() {
        didFail = false
    }

    /// Confirms the owner before a setting weakens the lock.
    ///
    /// - Returns: `true` when the change may go ahead.
    public func confirmWeakening() async -> Bool {
        guard authenticator.canAuthenticate() else { return true }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await authenticator.authenticate(reason: Self.changeReason)
    }

    private static var unlockReason: String {
        L("Finanzen entsperren", "Unlock Finance")
    }

    private static var changeReason: String {
        L("Sperre der Finanzen ändern", "Change the Finance lock")
    }
}
