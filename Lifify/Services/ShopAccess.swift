import Foundation

/// Whether the wallet may pay for something the person buys in the shop.
/// A negative balance locks every manual purchase, including free ones.
/// Automatic charges such as fast food do not ask this rule and still book.
enum ShopAccess: Equatable {
    case open
    case notEnoughCoins
    case locked

    static func isLocked(balance: Int) -> Bool {
        balance < 0
    }

    static func check(balance: Int, price: Int) -> ShopAccess {
        if isLocked(balance: balance) { return .locked }
        return balance >= price ? .open : .notEnoughCoins
    }

    /// How many coins bring a locked wallet back to zero.
    static func coinsToUnlock(balance: Int) -> Int {
        max(-balance, 0)
    }
}
