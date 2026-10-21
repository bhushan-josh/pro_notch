import NotchCore

public enum BatterySettings {
    public static let showPowerActivity = SettingKey("battery.showPowerActivity", default: true)
    public static let playSoundOnCharge = SettingKey("battery.playSoundOnCharge", default: true)
    public static let hidePercentage = SettingKey("battery.hidePercentage", default: false)
    public static let warnOnLowBattery = SettingKey("battery.warnOnLowBattery", default: true)
    public static let lowBatteryThreshold = SettingKey("battery.lowBatteryThreshold", default: 20)
    public static let playSoundOnLowBattery = SettingKey("battery.playSoundOnLowBattery", default: true)
    public static let notifyOnLowPowerMode = SettingKey("battery.notifyOnLowPowerMode", default: true)
}
