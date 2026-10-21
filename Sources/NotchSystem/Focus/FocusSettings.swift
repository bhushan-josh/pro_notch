import NotchCore

public enum FocusSettings {
    public static let enabled = SettingKey("focus.enabled", default: true)
    public static let duration = SettingKey("focus.duration", default: 2.0)
    public static let playSoundOnSleepFocus = SettingKey("focus.playSoundOnSleepFocus", default: true)

    public static let allowVolumeWhenFocused = SettingKey("focus.allowVolumeWhenFocused", default: true)
    public static let allowBrightnessWhenFocused = SettingKey("focus.allowBrightnessWhenFocused", default: true)
    public static let allowBatteryWhenFocused = SettingKey("focus.allowBatteryWhenFocused", default: true)
    public static let allowConnectivityWhenFocused = SettingKey("focus.allowConnectivityWhenFocused", default: true)
}
