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
                    "Lifify gleicht den Kalender beim Öffnen ab, sobald der Zugriff erlaubt ist. Apple liefert wiederkehrende Termine etwa ein Jahr im Voraus. Neue Termine einer Serie behalten die verknüpfte Challenge, und Trainings, die an dieser Challenge hängen, bekommen diese Termine dazu. Hier kann derselbe Abgleich von Hand gestartet werden.",
                    "Lifify syncs the calendar when it opens, once access is allowed. Apple provides recurring events about one year ahead. New events in a series keep the linked challenge, and workouts linked to that challenge receive those events. The same sync can be started here by hand."
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
