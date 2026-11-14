import AppIntents
import Foundation
import SwiftData

enum BankNoticeAccountChoice: String, AppEnum {
    case sparkasse
    case tradeRepublic

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Konto")
    }

    static var caseDisplayRepresentations: [BankNoticeAccountChoice: DisplayRepresentation] {
        [
            .sparkasse: "Sparkasse",
            .tradeRepublic: "Trade Republic"
        ]
    }

    var bank: BankNoticeBank {
        switch self {
        case .sparkasse: .sparkasse
        case .tradeRepublic: .tradeRepublic
        }
    }
}

struct RecordBankNoticeIntent: AppIntent {
    static var title: LocalizedStringResource { "Bankmitteilung buchen" }
    static var description: IntentDescription {
        IntentDescription("Bucht den Text einer Mitteilung auf das Sparkassen- oder Trade-Republic-Konto.")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Mitteilung")
    var notification: String

    @Parameter(title: "Konto")
    var account: BankNoticeAccountChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await BankNoticeIntake.commitFromShortcut(text: notification, bank: account.bank)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

extension BankNoticeIntake {
    static func commitFromShortcut(text: String, bank: BankNoticeBank) -> String {
        guard let container = LififyDatabase.container else { return BankNoticeCopy.unavailable }
        return commit(text: text, bank: bank, context: ModelContext(container))
    }
}

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
    }
}
