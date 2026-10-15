import AudioToolbox
import Foundation

enum RestChime {
    static let storageKey = "restChimeSoundID"

    struct Tone: Identifiable, Hashable {
        var id: Int
        var name: String
    }

    static let tones: [Tone] = [
        Tone(id: 1005, name: "Alarm"),
        Tone(id: 1000, name: "New Mail"),
        Tone(id: 1001, name: "Mail Sent"),
        Tone(id: 1002, name: "Voicemail"),
        Tone(id: 1003, name: "Received Message"),
        Tone(id: 1004, name: "Sent Message"),
        Tone(id: 1007, name: "SMS 1"),
        Tone(id: 1008, name: "SMS 2"),
        Tone(id: 1009, name: "SMS 3"),
        Tone(id: 1010, name: "SMS 4"),
        Tone(id: 1013, name: "SMS 5"),
        Tone(id: 1014, name: "SMS 6"),
        Tone(id: 1020, name: "Anticipate"),
        Tone(id: 1021, name: "Bloom"),
        Tone(id: 1022, name: "Calypso"),
        Tone(id: 1023, name: "Choo Choo"),
        Tone(id: 1024, name: "Descent"),
        Tone(id: 1025, name: "Fanfare"),
        Tone(id: 1026, name: "Ladder"),
        Tone(id: 1027, name: "Minuet"),
        Tone(id: 1028, name: "News Flash"),
        Tone(id: 1029, name: "Noir"),
        Tone(id: 1030, name: "Sherwood Forest"),
        Tone(id: 1031, name: "Spell"),
        Tone(id: 1032, name: "Suspense"),
        Tone(id: 1033, name: "Telegraph"),
        Tone(id: 1034, name: "Tiptoes"),
        Tone(id: 1035, name: "Typewriters"),
        Tone(id: 1036, name: "Update")
    ]

    static var selectedID: Int {
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Int ?? 1005
        return tones.contains { $0.id == stored } ? stored : 1005
    }

    static var selectedName: String {
        tones.first { $0.id == selectedID }?.name ?? "Alarm"
    }

    static func play() {
        AudioServicesPlayAlertSound(SystemSoundID(selectedID))
    }

    static func preview(_ id: Int) {
        AudioServicesPlayAlertSound(SystemSoundID(id))
    }
}
