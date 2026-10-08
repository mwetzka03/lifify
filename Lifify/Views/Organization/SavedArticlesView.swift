import SwiftData
import SwiftUI

struct SavedArticlesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedArticle.savedAt, order: .reverse) private var articles: [SavedArticle]
    @State private var showingNew = false

    var body: some View {
        List {
            ForEach(articles) { article in
                VStack(alignment: .leading, spacing: 5) {
                    Text(article.title).font(.headline)
                    if !article.notes.isEmpty {
                        Text(article.notes).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: article.urlString), !article.urlString.isEmpty {
                        Link(destination: url) {
                            Label(L("Im Browser öffnen", "Open in browser"), systemImage: "safari")
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .onDelete { offsets in
                offsets.map { articles[$0] }.forEach(context.delete)
                try? context.save()
            }
        }
        .overlay {
            if articles.isEmpty { ContentUnavailableView(L("Keine gespeicherten Artikel", "No saved articles"), systemImage: "bookmark") }
        }
        .navigationTitle(L("Artikel", "Articles"))
        .toolbar { Button { showingNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showingNew) { SavedArticleForm() }
    }
}

private struct SavedArticleForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var url = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("Titel", "Title"), text: $title)
                TextField("URL", text: $url).textInputAutocapitalization(.never).keyboardType(.URL)
                TextField(L("Notiz", "Note"), text: $notes, axis: .vertical)
            }
            .navigationTitle(L("Artikel speichern", "Save article"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Abbrechen", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Speichern", "Save")) {
                        guard !title.isEmpty else { return }
                        context.insert(SavedArticle(title: title, urlString: url, notes: notes))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
