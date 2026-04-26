import AppKit

final class SoundManager {

    static let shared = SoundManager()
    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundFeedback") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundFeedback") }
    }

    func playStart() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }

    func playStop() {
        guard isEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    func playCancel() {
        guard isEnabled else { return }
        NSSound(named: "Basso")?.play()
    }
}
