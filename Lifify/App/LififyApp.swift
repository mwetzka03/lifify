import SwiftData
import SwiftUI

@main
struct LififyApp: App {
    private let containerResult: Result<ModelContainer, Error> = {
        let schema = Schema(versionedSchema: LififySchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return .success(try ModelContainer(
                for: schema,
                migrationPlan: LififyMigrationPlan.self,
                configurations: [configuration]
            ))
        } catch let legacyError {
            let fallbackConfiguration = ModelConfiguration(
                "LififyCurrent",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                return .success(try ModelContainer(
                    for: schema,
                    migrationPlan: LififyMigrationPlan.self,
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
                RootView()
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
