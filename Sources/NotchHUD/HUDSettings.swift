import SwiftUI
import NotchCore

public enum HUDSpeed: String, CaseIterable, Sendable {
    case smooth, fast, instant

    public var title: String {
        switch self {
        case .smooth: "Smooth"
        case .fast: "Fast"
        case .instant: "Instant"
        }
    }

    var animation: Animation? {
        switch self {
        case .smooth: .smooth(duration: 0.32)
        case .fast: .snappy(duration: 0.14)
        case .instant: nil
        }
    }
}

public enum HUDSettings {
    public static let duration = SettingKey("hud.duration", default: 1.5)
    public static let speed = SettingKey("hud.speed", default: HUDSpeed.smooth)
    public static let enableVolume = SettingKey("hud.enableVolume", default: true)
    public static let enableBrightness = SettingKey("hud.enableBrightness", default: true)
    public static let enableKeyboard = SettingKey("hud.enableKeyboard", default: true)
    public static let showPercentage = SettingKey("hud.showPercentage", default: false)
    public static let replaceSystemHUD = SettingKey("hud.replaceSystemHUD", default: true)
    public static let betterDisplayIntegration = SettingKey("hud.betterDisplayIntegration", default: true)
    public static let notifyOnOutputChange = SettingKey("sound.notifyOnOutputChange", default: true)

    static let accessibilityRequested = SettingKey("hud.accessibilityRequested", default: false)
}
