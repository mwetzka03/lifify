import SwiftData
import SwiftUI

struct SystemCalendarSyncView: View {
    @Environment(\.modelContext) private var context
    @Query private var events: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @StateObject private var service = EventKitSyncService()

    var body: some View {
        Form {
            Section {
                Text(L(
                    "Lifify verwendet den iOS-Systemkalender. Wiederkehrende Erinnerungen können als Challenges übernommen werden; neue Challenges und ihr Erledigt-Status werden mit Apple Erinnerungen synchronisiert.",
                    "Lifify uses the iOS system calendar. Recurring reminders can become challenges; new challenges and their completion status are synced with Apple Reminders."
                ))
                Button {
                    Task {
                        await service.sync(context: context, existingEvents: events, existingChallenges: challenges)
                    }
                } label: {
                    if service.isSyncing {
                        ProgressView()
                    } else {
                        Label(L("Jetzt synchronisieren", "Sync now"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(service.isSyncing)
            } header: {
                Text(L("Systemintegration", "System integration"))
            }
            Section {
                LabeledContent(L("Importierte Termine", "Imported events"), value: "\(events.filter { $0.externalIdentifier != nil && !$0.isReminderSuggestion }.count)")
                LabeledContent(L("Importierte Erinnerungen", "Imported reminders"), value: "\(events.filter(\.isReminderSuggestion).count)")
            }
        }
        .navigationTitle(L("Kalender-Sync", "Calendar sync"))
        .alert(L("Synchronisierung", "Sync"), isPresented: Binding(
            get: { service.message != nil },
            set: { if !$0 { service.message = nil } }
        )) {
            Button("OK") { service.message = nil }
        } message: {
            Text(service.message ?? "")
        }
    }
}
