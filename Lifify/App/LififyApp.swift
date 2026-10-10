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
        } catch {
            return .failure(error)
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
