import AppKit

public enum Haptics {
    @MainActor
    public static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard Defaults[CoreSettings.haptics] else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Short UI sounds drawn from the system sound library rather than bundled audio.
public enum SystemSound: String, CaseIterable, Sendable {
    case lock = "system/media_paused.caf"
    case unlock = "system/acknowledgment_sent.caf"
    case chime = "Glass"
    case event = "Ping"
    case lowBattery = "Basso"
    case charging = "system/media_handoff.caf"
    case focus = "Purr"
    case notification = "Tink"
    case pop = "Pop"
    case connect = "siri/jbl_begin_short.caf"

    private static let componentSounds = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/"

    @MainActor
    public func play(volume: Float = 0.6) {
        let sound: NSSound?
        if rawValue.contains("/") {
            sound = NSSound(contentsOf: URL(fileURLWithPath: Self.componentSounds + rawValue), byReference: true)
        } else {
            sound = NSSound(named: NSSound.Name(rawValue))
        }
        guard let sound = sound ?? NSSound(named: "Tink") else { return }
        sound.volume = volume
        sound.play()
    }
}
