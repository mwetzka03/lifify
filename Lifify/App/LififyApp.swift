import SwiftData
import SwiftUI
import UserNotifications

@main
struct LififyApp: App {
    @State private var containerResult: Result<ModelContainer, Error>

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        AppClock.resetSimulatedDay()
        let result = StoreRecoveryService.openContainer()
        _containerResult = State(initialValue: result)
        if case .success(let container) = result {
            LififyDatabase.container = container
        }
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                AppEntryView()
                    .modelContainer(container)
            case .failure(let error):
                StoreFailureView(error: error) { container in
                    LififyDatabase.container = container
                    containerResult = .success(container)
                }
            }
        }
    }
}

@MainActor
enum LififyDatabase {
    static var container: ModelContainer?
}
