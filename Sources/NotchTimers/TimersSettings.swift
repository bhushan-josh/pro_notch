import Foundation
import NotchCore

public enum TimerSound: String, CaseIterable, Sendable {
    case glass, ping, tink, pop, purr, basso

    public var title: String {
        switch self {
        case .glass: "Glass"
        case .ping: "Ping"
        case .tink: "Tink"
        case .pop: "Pop"
        case .purr: "Purr"
        case .basso: "Basso"
        }
    }

    var systemSound: SystemSound {
        switch self {
        case .glass: .chime
        case .ping: .event
        case .tink: .notification
        case .pop: .pop
        case .purr: .focus
        case .basso: .lowBattery
        }
    }
}

public enum TimersSettings {
    public static let showTab = SettingKey("timers.showTab", default: false)
    public static let showInNotch = SettingKey("timers.showInNotch", default: true)
    public static let showOnLockScreen = SettingKey("timers.showOnLockScreen", default: true)
    public static let sound = SettingKey("timers.sound", default: TimerSound.glass)
    public static let repeatSound = SettingKey("timers.repeatSound", default: true)
    /// Preset durations in whole minutes, stored as strings so `@AppStorage`-style string arrays can hold them.
    public static let presets = SettingKey("timers.presets", default: ["1", "3", "5", "10", "15", "25"])
    /// Seconds last entered in the custom duration picker.
    public static let lastCustom = SettingKey("timers.lastCustom", default: 300)

    static let maxPresetMinutes = 600

    static var presetMinutes: [Int] {
        get { normalized(Defaults[presets].compactMap { Int($0) }) }
        set { Defaults[presets] = normalized(newValue).map(String.init) }
    }

    static func normalized(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.filter { (1...maxPresetMinutes).contains($0) })).sorted()
    }
}
