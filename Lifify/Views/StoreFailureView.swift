import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Shown when the database of a finished app cannot be opened. Nothing is moved until the person restores.
struct StoreFailureView: View {
    let error: Error
    let onRecovered: (ModelContainer) -> Void
    @State private var choosingBackup = false
    @State private var restoreError: String?

    var body: some View {
        ContentUnavailableView {
            Label(L("Datenspeicher nicht verfügbar", "Data store unavailable"), systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 8) {
                Text(L(
                    "Deine Daten wurden nicht verändert. Du kannst eine Sicherung der gesamten App wiederherstellen. Der bisherige Speicher bleibt dabei in einem Archivordner auf dem Gerät.",
                    "Your data was not changed. You can restore a backup of the entire app. The current store stays in an archive folder on this device."
                ))
                Text(error.localizedDescription)
                    .font(.caption)
            }
        } actions: {
            Button(L("Sicherung wiederherstellen", "Restore backup")) {
                choosingBackup = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
            restore(result)
        }
        .alert(L("Wiederherstellung fehlgeschlagen", "Restore failed"), isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            onRecovered(try StoreRecoveryService.recover(from: Data(contentsOf: url)))
        } catch {
            restoreError = error.localizedDescription
        }
    }
}
