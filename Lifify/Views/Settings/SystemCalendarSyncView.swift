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
    @AppStorage(ReminderListChoice.storageKey) private var listID = ""
    @State private var lists: [ReminderListOption] = []

    /// Names the list that automatic picks.
    private var automaticTitle: String {
        let picked = ReminderListChoice.pick(from: lists, stored: nil)
        let name = lists.first { $0.id == picked }?.title ?? L("Standardliste", "default list")
        return "\(L("Automatisch", "Automatic")) (\(name))"
    }

    var body: some View {
        AppForm {
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
                Picker(L("Liste für Challenges", "List for challenges"), selection: $listID) {
                    Text(automaticTitle).tag("")
                    ForEach(lists) { Text($0.title).tag($0.id) }
                }
            } header: {
                Text(L("Erinnerungen", "Reminders"))
            } footer: {
                Text(L(
                    "In diese Liste legt Lifify neue Challenges als Erinnerung an. Automatisch heißt: eine Liste namens To-Do, sonst die Standardliste. Bestehende Erinnerungen bleiben in ihrer Liste.",
                    "Lifify creates new challenges as reminders in this list. Automatic means a list named To-Do, else the default list. Existing reminders stay in their list."
                ))
            }
            .appGlassRow()
            .task { lists = await CalendarBridge.current.reminderLists() }
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
