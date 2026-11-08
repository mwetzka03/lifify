import Foundation
import SwiftUI

struct SymbolChoice: Identifiable, Equatable {
    var name: String
    var title: String
    var id: String { name }
}

enum AppSymbol {
    static let assetPrefix = "symbol."

    static func assetName(in stored: String) -> String? {
        guard stored.hasPrefix(assetPrefix) else { return nil }
        let name = String(stored.dropFirst(assetPrefix.count))
        return name.isEmpty ? nil : name
    }
}

struct AppSymbolImage: View {
    var name: String

    var body: some View {
        if let asset = AppSymbol.assetName(in: name) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: name)
        }
    }
}

enum SymbolCatalog {
    static var names: [String] { choices().map(\.name) }

    static func choices() -> [SymbolChoice] {
        let symbols = [
            "banknote", "eurosign.circle", "creditcard", "building.columns", "wallet.pass",
            "cart", "basket", "bag", "gift", "shippingbox", "fork.knife", "cup.and.saucer",
            "takeoutbag.and.cup.and.straw", "mug", "wineglass", "waterbottle",
            "house", "key", "bolt", "drop", "flame", "wifi", "phone", "laptopcomputer",
            "car", "bus", "tram", "bicycle", "airplane", "fuelpump", "parkingsign.circle",
            "heart", "cross.case", "pills", "syringe", "bandage", "stethoscope", "lungs",
            "brain.head.profile", "waveform.path.ecg", "bed.double", "moon.zzz",
            "figure.walk", "figure.run", "figure.yoga", "figure.pool.swim", "figure.cooldown",
            "dumbbell", "sportscourt", "soccerball", "basketball", "tennis.racket",
            "book", "graduationcap", "briefcase", "hammer", "wrench.and.screwdriver",
            "gamecontroller", "music.note", "film", "tv", "camera", "paintpalette",
            "pawprint", "leaf", "tree", "camera.macro", "sun.max", "moon", "cloud.rain",
            "calendar", "clock", "alarm", "checkmark.circle", "target", "flag",
            "star", "sparkles", "lightbulb", "bell", "person.2", "figure.2.and.child.holdinghands",
            "chart.line.uptrend.xyaxis", "chart.pie", "percent", "repeat", "arrow.left.arrow.right"
        ]
        return symbols.map { SymbolChoice(name: $0, title: $0) } + [
            SymbolChoice(name: "symbol.hemp-leaf", title: L("Hanfblatt", "Hemp leaf")),
            SymbolChoice(name: "symbol.cigarette", title: L("Zigarette", "Cigarette"))
        ]
    }
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
                AppSymbolImage(name: selection)
                    .font(AppChrome.font(.value))
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
                        ForEach(SymbolCatalog.choices()) { symbol in
                            Button {
                                selection = symbol.name
                                isPresented = false
                            } label: {
                                AppSymbolImage(name: symbol.name)
                                    .font(AppChrome.font(.value))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .appGlassCard(radius: 12)
                                    .overlay(alignment: .topTrailing) {
                                        if selection == symbol.name {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(AppChrome.font(.caption))
                                                .foregroundStyle(Color.accentColor)
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.title)
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
