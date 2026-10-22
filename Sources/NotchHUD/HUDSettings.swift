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

    public static let levelColorMode = SettingKey("hud.levelColors.mode", default: LevelColorMode.smooth)
    public static let levelColorsVolume = SettingKey("hud.levelColors.volume", default: true)
    public static let levelColorsBrightness = SettingKey("hud.levelColors.brightness", default: true)
    public static let levelColorsKeyboard = SettingKey("hud.levelColors.keyboard", default: false)
    public static let levelColorsTintIcon = SettingKey("hud.levelColors.tintIcon", default: false)
    public static let levelMidThreshold = SettingKey("hud.levelColors.midThreshold", default: 0.5)
    public static let levelHighThreshold = SettingKey("hud.levelColors.highThreshold", default: 0.8)
    public static let levelLowColor = SettingKey("hud.levelColors.low", default: "#34C759")
    public static let levelMidColor = SettingKey("hud.levelColors.mid", default: "#FFCC00")
    public static let levelHighColor = SettingKey("hud.levelColors.high", default: "#FF3B30")

    static let accessibilityRequested = SettingKey("hud.accessibilityRequested", default: false)

    static var levelColors: LevelColors {
        LevelColors(
            mode: Defaults[levelColorMode],
            low: Color(hex: Defaults[levelLowColor]) ?? .green,
            mid: Color(hex: Defaults[levelMidColor]) ?? .yellow,
            high: Color(hex: Defaults[levelHighColor]) ?? .red,
            midThreshold: Defaults[levelMidThreshold],
            highThreshold: Defaults[levelHighThreshold]
        )
    }

    static let levelColorKeys = [
        levelColorMode.name, levelColorsVolume.name, levelColorsBrightness.name, levelColorsKeyboard.name,
        levelColorsTintIcon.name, levelMidThreshold.name, levelHighThreshold.name,
        levelLowColor.name, levelMidColor.name, levelHighColor.name,
    ]
}
