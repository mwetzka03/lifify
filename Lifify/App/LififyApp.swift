import SwiftData
import SwiftUI

@main
struct LififyApp: App {
    private let containerResult: Result<ModelContainer, Error> = {
        let schema = Schema(LififySchemaV2.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return .success(try ModelContainer(
                for: schema,
                configurations: [configuration]
            ))
        } catch let legacyError {
            let fallbackConfiguration = ModelConfiguration(
                "LififyRecoveryV2",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                return .success(try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                ))
            } catch {
                let combinedError = NSError(
                    domain: "com.mwetzka03.lifify.storage",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(error.localizedDescription) (\(legacyError.localizedDescription))"
                    ]
                )
                return .failure(combinedError)
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                AppEntryView()
                    .modelContainer(container)
            case .failure(let error):
                ContentUnavailableView(
                    L("Datenspeicher nicht verfügbar", "Data store unavailable"),
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(error.localizedDescription)
                )
                .padding()
            }
        }
    }
}
