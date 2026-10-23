import NotchCore

public enum PrivacySettings {
    public static let camera = SettingKey("privacy.camera", default: true)
    public static let microphone = SettingKey("privacy.microphone", default: true)
    public static let showDuration = SettingKey("privacy.showDuration", default: true)
    public static let compactMode = SettingKey("privacy.compactMode", default: true)
    public static let playSound = SettingKey("privacy.playSound", default: false)

    static let observed = [camera.name, microphone.name, showDuration.name, compactMode.name]
}
