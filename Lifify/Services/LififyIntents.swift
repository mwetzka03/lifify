import AppIntents
import Foundation
import LififyChallenges
import LififyCore
import LififyHealth
import SwiftData

/// Gives intents the database, also when the system started the app without a screen.
@MainActor
enum IntentStore {
    /// Returns a context on the app's database.
    static func context() throws -> ModelContext {
        if let container = LififyDatabase.container { return ModelContext(container) }
        LififyAssembly.install()
        let container = try StoreRecoveryService.makeContainer()
        LififyDatabase.container = container
        return ModelContext(container)
    }
}

/// A challenge that Siri and Shortcuts can name.
struct ChallengeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Challenge" }
    static var defaultQuery: ChallengeEntityQuery { ChallengeEntityQuery() }

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

/// Finds the challenges that can be checked off today.
struct ChallengeEntityQuery: EntityStringQuery {
    /// Returns the challenges with the given IDs.
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ChallengeEntity] {
        let challenges = try IntentStore.context().fetch(FetchDescriptor<ChallengeItem>())
        return challenges.filter { identifiers.contains($0.id) }.map { ChallengeEntity(id: $0.id, title: $0.title) }
    }

    /// Finds open challenges by name.
    @MainActor
    func entities(matching string: String) async throws -> [ChallengeEntity] {
        try checkableEntities().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    /// Lists the open challenges of today.
    @MainActor
    func suggestedEntities() async throws -> [ChallengeEntity] {
        try checkableEntities()
    }

    /// Lists the open challenges that allow a check-off.
    @MainActor
    private func checkableEntities() throws -> [ChallengeEntity] {
        SiriActions.openChallenges(context: try IntentStore.context())
            .filter(SiriActions.canCheckOff)
            .map { ChallengeEntity(id: $0.id, title: $0.title) }
    }
}

/// Checks a challenge off for today.
struct CheckOffChallengeIntent: AppIntent {
    static var title: LocalizedStringResource { "Challenge abhaken" }
    static var description: IntentDescription { IntentDescription("Hakt eine offene Challenge für heute ab.") }

    @Parameter(title: "Challenge")
    var challenge: ChallengeEntity

    /// Checks off and says the result.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = SiriActions.checkOff(id: challenge.id, context: try IntentStore.context())
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Enters a meal for today.
struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource { "Mahlzeit eintragen" }
    static var description: IntentDescription { IntentDescription("Trägt eine Mahlzeit für heute ein. Ein bekannter Favorit übernimmt seine Nährwerte.") }

    @Parameter(title: "Mahlzeit")
    var meal: String

    @Parameter(title: "Kalorien")
    var calories: Int?

    /// Enters the meal and says the result.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sessions = WorkoutStore().sessions
        let message = SiriActions.logMeal(title: meal, calories: calories, context: try IntentStore.context(), sessions: sessions)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Says the remaining budget. The device must be unlocked, because the answer is financial.
struct RemainingBudgetIntent: AppIntent {
    static var title: LocalizedStringResource { "Restbudget abfragen" }
    static var description: IntentDescription { IntentDescription("Nennt das verbleibende Budget und den Betrag pro Tag.") }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    /// Reads the budget and says it.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = SiriActions.remainingBudget(context: try IntentStore.context())
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
