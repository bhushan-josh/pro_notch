import Foundation
import MapKit
import NotchCore

public enum CalendarTransport: String, CaseIterable, Sendable {
    case drive, transit, walk

    public var title: String {
        switch self {
        case .drive: "Drive"
        case .transit: "Transit"
        case .walk: "Walk"
        }
    }

    public var symbol: String {
        switch self {
        case .drive: "car.fill"
        case .transit: "tram.fill"
        case .walk: "figure.walk"
        }
    }

    var directionsType: MKDirectionsTransportType {
        switch self {
        case .drive: .automobile
        case .transit: .transit
        case .walk: .walking
        }
    }
}

public enum CalendarSettings {
    public static let enabled = SettingKey("calendar.enabled", default: true)
    /// Empty means every event calendar.
    public static let selectedCalendarIDs = SettingKey("calendar.selectedCalendarIDs", default: [String]())

    public static let alwaysShowMonthView = SettingKey("calendar.alwaysShowMonthView", default: false)
    public static let useEventIndicators = SettingKey("calendar.useEventIndicators", default: true)
    public static let useCalendarColor = SettingKey("calendar.useCalendarColor", default: true)
    public static let showWeatherOnEmptyDay = SettingKey("calendar.showWeatherOnEmptyDay", default: true)

    public static let notifyBeforeEvent = SettingKey("calendar.notifyBeforeEvent", default: true)
    public static let timeBeforeEvent = SettingKey("calendar.timeBeforeEvent", default: 5)
    public static let notifyWhenEventStarts = SettingKey("calendar.notifyWhenEventStarts", default: true)
    public static let disableActivityDuringEvents = SettingKey("calendar.disableActivityDuringEvents", default: false)
    public static let useColoredCalendarIndicator = SettingKey("calendar.useColoredCalendarIndicator", default: true)
    public static let playSoundOnEvent = SettingKey("calendar.playSoundOnEvent", default: true)

    public static let notifyWhenTimeToLeave = SettingKey("calendar.notifyWhenTimeToLeave", default: false)
    public static let transport = SettingKey("calendar.transport", default: CalendarTransport.drive)
    public static let timeToLeaveBuffer = SettingKey("calendar.timeToLeaveBuffer", default: 5)
    /// Seconds the "Leave now" alert stays on screen.
    public static let timeToLeaveDuration = SettingKey("calendar.timeToLeaveDuration", default: 10.0)
    public static let playSoundOnNotification = SettingKey("calendar.playSoundOnNotification", default: true)

    public static let playHourlyChime = SettingKey("calendar.playHourlyChime", default: false)

    static let dismissedEventIDs = SettingKey("calendar.dismissedEventIDs", default: [String]())
    static let dismissedDay = SettingKey("calendar.dismissedDay", default: "")
}
