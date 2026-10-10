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

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(SymbolCatalog.names, id: \.self) { symbol in
                Label(symbol, systemImage: symbol).tag(symbol)
            }
        }
    }
}
