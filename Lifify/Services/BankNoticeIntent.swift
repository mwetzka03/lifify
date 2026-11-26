import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import AppIntents
import Foundation
import SwiftData

/// The bank chosen in a shortcut.
enum BankNoticeAccountChoice: String, AppEnum {
    case sparkasse
    case tradeRepublic
    case paypal

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Konto")
    }

    static var caseDisplayRepresentations: [BankNoticeAccountChoice: DisplayRepresentation] {
        [
            .sparkasse: "Sparkasse",
            .tradeRepublic: "Trade Republic",
            .paypal: "PayPal"
        ]
    }

    var bank: BankNoticeBank {
        switch self {
        case .sparkasse: .sparkasse
        case .tradeRepublic: .tradeRepublic
        case .paypal: .paypal
        }
    }
}

/// The Shortcuts action that books a bank notice.
struct RecordBankNoticeIntent: AppIntent {
    static var title: LocalizedStringResource { "Bankmitteilung buchen" }
    static var description: IntentDescription {
        IntentDescription("Bucht den Text einer Mitteilung auf das Sparkassen- oder Trade-Republic-Konto.")
    }
    /// Books in the background, so a notice never pulls Lifify to the front.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Mitteilung")
    var notification: String

    @Parameter(title: "Konto")
    var account: BankNoticeAccountChoice

    /// Books the notice and shows the result, like "12,50 € gebucht: REWE".
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await BankNoticeIntake.commitFromShortcut(text: notification, bank: account.bank)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Shortcut access to the notice intake.
extension BankNoticeIntake {
    /// Books a notice into the shared database, also when the system started Lifify without a screen.
    ///
    /// Budget alerts and widgets are updated before the action ends, because a background run
    /// may stop right after it.
    ///
    /// - Parameters:
    ///   - text: The notice.
    ///   - bank: The bank it came from.
    /// - Returns: The confirmation shown by Shortcuts.
    static func commitFromShortcut(text: String, bank: BankNoticeBank) async -> String {
        guard let context = try? IntentStore.context() else { return BankNoticeCopy.unavailable }
        var booked: LedgerEntry?
        let message = commit(text: text, bank: bank, context: context) { booked = $0 }
        guard let booked else { return message }
        await BudgetAlertService.check(context: context)
        WidgetPublisher.refreshFinance(context: context)
        return BankNoticeCopy.booked(booked)
    }
}

/// The app's shortcuts.
struct LififyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordBankNoticeIntent(),
            phrases: [
                "Bankmitteilung in \(.applicationName) buchen",
                "Record a bank notice in \(.applicationName)"
            ],
            shortTitle: "Bankmitteilung",
            systemImageName: "building.columns"
        )
        AppShortcut(
            intent: CheckOffChallengeIntent(),
            phrases: [
                "Challenge in \(.applicationName) abhaken",
                "\(\.$challenge) in \(.applicationName) abhaken",
                "Check off a challenge in \(.applicationName)"
            ],
            shortTitle: "Challenge abhaken",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: LogMealIntent(),
            phrases: [
                "Mahlzeit in \(.applicationName) eintragen",
                "Log a meal in \(.applicationName)"
            ],
            shortTitle: "Mahlzeit",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: RemainingBudgetIntent(),
            phrases: [
                "Restbudget in \(.applicationName)",
                "Wie viel Budget habe ich noch in \(.applicationName)",
                "Remaining budget in \(.applicationName)"
            ],
            shortTitle: "Restbudget",
            systemImageName: "eurosign.circle"
        )
    }
}
