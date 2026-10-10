import Foundation
import SwiftUI

enum SymbolCatalog {
    static let names = [
        "banknote", "eurosign.circle", "creditcard", "building.columns", "wallet.pass",
        "cart", "basket", "bag", "gift", "shippingbox", "fork.knife", "cup.and.saucer",
        "house", "key", "bolt", "drop", "flame", "wifi", "phone", "laptopcomputer",
        "car", "bus", "tram", "bicycle", "airplane", "fuelpump", "parkingsign.circle",
        "heart", "cross.case", "pills", "figure.walk", "figure.run", "dumbbell",
        "book", "graduationcap", "briefcase", "hammer", "wrench.and.screwdriver",
        "gamecontroller", "music.note", "film", "tv", "camera", "paintpalette",
        "pawprint", "leaf", "tree", "sun.max", "moon", "cloud.rain",
        "calendar", "clock", "alarm", "checkmark.circle", "target", "flag",
        "star", "sparkles", "lightbulb", "bell", "person.2", "figure.2.and.child.holdinghands",
        "chart.line.uptrend.xyaxis", "chart.pie", "percent", "repeat", "arrow.left.arrow.right"
    ]
}

enum IconPreferenceStore {
    private static func key(for id: UUID) -> String {
        "icon.\(id.uuidString)"
    }

    static func icon(for id: UUID, fallback: String) -> String {
        UserDefaults.standard.string(forKey: key(for: id)) ?? fallback
    }

    static func storedIcon(for id: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(for: id))
    }

    static func set(_ icon: String, for id: UUID) {
        UserDefaults.standard.set(icon, forKey: key(for: id))
    }

    static func remove(for id: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: id))
    }
}

struct SymbolPicker: View {
    let title: String
    @Binding var selection: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: selection)
                    .font(.title3)
            }
            .foregroundStyle(.primary)
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 5),
                        spacing: 14
                    ) {
                        ForEach(Array(SymbolCatalog.names.enumerated()), id: \.element) { index, symbol in
                            Button {
                                selection = symbol
                                isPresented = false
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(
                                        selection == symbol ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if selection == symbol {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.accentColor)
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(title) \(index + 1)")
                        }
                    }
                    .padding()
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Fertig", "Done")) { isPresented = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
