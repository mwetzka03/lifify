import Foundation
import LififyCore

/// Whether the wallet may pay for something the person buys in the shop.
/// A negative balance locks every manual purchase, including free ones.
/// Automatic charges such as fast food do not ask this rule and still book.
public enum ShopAccess: Equatable, Sendable {
    case open
    case notEnoughCoins
    case locked

    public static func isLocked(balance: Int) -> Bool {
        balance < 0
    }

    public static func check(balance: Int, price: Int) -> ShopAccess {
        if isLocked(balance: balance) { return .locked }
        return balance >= price ? .open : .notEnoughCoins
    }

    /// How many coins bring a locked wallet back to zero.
    public static func coinsToUnlock(balance: Int) -> Int {
        max(-balance, 0)
    }
}
