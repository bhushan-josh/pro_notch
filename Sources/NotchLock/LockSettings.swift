import Foundation
import NotchCore

public enum LockWidgetStyle: String, CaseIterable, Sendable {
    case clear, frosted, glass

    public var title: String {
        switch self {
        case .clear: "Clear"
        case .frosted: "Frosted"
        case .glass: "Glass"
        }
    }
}

public enum WeatherWidgetStyle: String, CaseIterable, Sendable {
    case conditions, precipitation, sun

    public var title: String {
        switch self {
        case .conditions: "Conditions"
        case .precipitation: "Precipitation"
        case .sun: "Sun"
        }
    }
}

public enum TemperatureUnitPreference: String, CaseIterable, Sendable {
    case automatic, celsius, fahrenheit

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .celsius: "Celsius"
        case .fahrenheit: "Fahrenheit"
        }
    }

    var usesFahrenheit: Bool {
        switch self {
        case .celsius: false
        case .fahrenheit: true
        case .automatic: UnitTemperature(forLocale: .current, usage: .weather) == .fahrenheit
        }
    }
}

public enum LockSettings {
    public static let showLockActivity = SettingKey("lockScreen.showLockActivity", default: true)
    public static let playSoundOnLock = SettingKey("lockScreen.playSoundOnLock", default: false)
    public static let playSoundOnUnlock = SettingKey("lockScreen.playSoundOnUnlock", default: false)

    public static let widgetsEnabled = SettingKey("lockScreen.widgetsEnabled", default: true)
    public static let widgetStyle = SettingKey("lockScreen.widgetStyle", default: LockWidgetStyle.frosted)
    public static let showMediaWidget = SettingKey("lockScreen.showMediaWidget", default: true)
    public static let showWeatherWidget = SettingKey("lockScreen.showWeatherWidget", default: true)
    public static let weatherStyle = SettingKey("lockScreen.weatherStyle", default: WeatherWidgetStyle.conditions)
    /// Points the widget stack moves down from its default spot below the clock; negative moves it up.
    public static let widgetOffset = SettingKey("lockScreen.widgetOffset", default: 0.0)
    public static let showOnScreenSaver = SettingKey("lockScreen.showOnScreenSaver", default: false)
    public static let keepAwake = SettingKey("lockScreen.keepAwake", default: false)

    public static let weatherUnit = SettingKey("weather.unit", default: TemperatureUnitPreference.automatic)
    public static let manualLocation = SettingKey("weather.manualLocation", default: "")
}
