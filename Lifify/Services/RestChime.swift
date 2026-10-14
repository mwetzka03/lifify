import AudioToolbox

enum RestChime {
    static func play() {
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}
