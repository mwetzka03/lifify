import Foundation
import LififyCore
import LififyFinance
import Testing
@testable import Lifify

/// A scripted Face ID prompt.
private final class StubAuthenticator: DeviceAuthenticator, @unchecked Sendable {
    var available = true
    var answer = true
    var prompts = 0
    var beforeAnswer: (@MainActor () -> Void)?

    func canAuthenticate() -> Bool { available }

    @MainActor
    func authenticate(reason: String) async -> Bool {
        prompts += 1
        beforeAnswer?()
        return answer
    }
}

extension LififyRuleTests {
    /// Finance opens only for the device owner and locks again in the background.
    @Suite("Finance lock")
    @MainActor
    struct FinanceLockTests {
        @Test func successUnlocksUntilTheBackground() async {
            let stub = StubAuthenticator()
            let lock = FinanceLock(authenticator: stub)
            #expect(!lock.isUnlocked)
            await lock.unlock()
            #expect(lock.isUnlocked)
            await lock.unlock()
            #expect(stub.prompts == 1)
            lock.lock()
            #expect(!lock.isUnlocked)
        }

        @Test func aCancelledPromptStaysLockedAndDoesNotRepeat() async {
            let stub = StubAuthenticator()
            stub.answer = false
            let lock = FinanceLock(authenticator: stub)
            await lock.unlock()
            #expect(!lock.isUnlocked)
            #expect(lock.didFail)
            lock.allowPrompt()
            #expect(!lock.didFail)
        }

        @Test func aLateSuccessAfterTheBackgroundIsIgnored() async {
            let stub = StubAuthenticator()
            let lock = FinanceLock(authenticator: stub)
            stub.beforeAnswer = { lock.lock() }
            await lock.unlock()
            #expect(!lock.isUnlocked)
        }

        @Test func aDeviceWithoutPasscodeIsNotLockedOut() async {
            let stub = StubAuthenticator()
            stub.available = false
            let lock = FinanceLock(authenticator: stub)
            await lock.unlock()
            #expect(lock.isUnlocked)
            #expect(stub.prompts == 0)
        }

        @Test func weakeningTheLockNeedsTheOwner() async {
            let stub = StubAuthenticator()
            stub.answer = false
            #expect(await !FinanceLock(authenticator: stub).confirmWeakening())
            stub.answer = true
            #expect(await FinanceLock(authenticator: stub).confirmWeakening())
        }

        @Test func widgetsFollowTheLockAndItsSwitch() async throws {
            try await withTestStore { store in
                #expect(FinanceLockSettings.isEnabled)
                #expect(!FinanceLockSettings.widgetsMayShowAmounts)
                store.defaults.set(true, forKey: FinanceLockSettings.widgetValuesKey)
                #expect(FinanceLockSettings.widgetsMayShowAmounts)
                store.defaults.set(false, forKey: FinanceLockSettings.widgetValuesKey)
                store.defaults.set(false, forKey: FinanceLockSettings.enabledKey)
                #expect(FinanceLockSettings.widgetsMayShowAmounts)
            }
        }

        @Test func lockChoicesStayOutOfBackups() {
            for scope in [BackupScope.all, .finance, .challenges, .training] {
                #expect(!BackupDefaults.belongs(FinanceLockSettings.enabledKey, to: scope))
                #expect(!BackupDefaults.belongs(FinanceLockSettings.widgetValuesKey, to: scope))
            }
        }
    }
}
