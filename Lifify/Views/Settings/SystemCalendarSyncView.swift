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
                    "Lifify verwendet den iOS-Systemkalender. Dadurch funktionieren iCloud, Google, Outlook und andere bereits auf dem iPhone eingerichtete Kalender, ohne Zugangsdaten in Lifify zu speichern.",
                    "Lifify uses the iOS system calendar. This supports iCloud, Google, Outlook and other calendars already configured on the iPhone without storing credentials in Lifify."
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
                LabeledContent(L("Importierte Termine", "Imported events"), value: "\(events.filter { $0.externalIdentifier != nil }.count)")
                LabeledContent(L("Importierte Erinnerungen", "Imported reminders"), value: "\(challenges.filter { $0.externalIdentifier != nil }.count)")
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
