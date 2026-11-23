import LififyCore
import LififyFinance
import LififyChallenges
import LififyHealth
import SwiftData
import SwiftUI

/// Starts the sync with the system calendar.
struct SystemCalendarSyncView: View {
    @Environment(\.modelContext) private var context
    @Query private var events: [ChallengeCalendarEvent]
    @Query private var challenges: [ChallengeItem]
    @StateObject private var service = EventKitSyncService()

    var body: some View {
        Form {
            Section {
                Text(L(
                    "Sobald der Zugriff da ist, gleicht Lifify den Kalender beim Öffnen ab. Hier kannst du denselben Abgleich von Hand starten.",
                    "Once access is allowed, Lifify syncs the calendar when it opens. You can start the same sync here by hand."
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
            .appGlassRow()
            Section {
                LabeledContent(L("Importierte Termine", "Imported events"), value: "\(events.filter { $0.externalIdentifier != nil && !$0.isReminderSuggestion }.count)")
                LabeledContent(L("Importierte Erinnerungen", "Imported reminders"), value: "\(events.filter(\.isReminderSuggestion).count)")
            }
            .appGlassRow()
        }
        .appGlassList()
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
