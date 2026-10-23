import SwiftUI
import Observation

public struct FocusModeInfo: Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var symbol: String
    public var color: Color

    public init(identifier: String, name: String, symbol: String, color: Color) {
        self.identifier = identifier
        self.name = name
        self.symbol = symbol
        self.color = color
    }
}

public struct WeatherSnapshot: Equatable, Sendable {
    public var temperature: Double
    public var high: Double
    public var low: Double
    public var conditionName: String
    public var symbol: String
    public var precipitationChance: Double
    public var sunrise: Date?
    public var sunset: Date?
    public var unitSymbol: String
    public var fetchedAt: Date

    public init(temperature: Double, high: Double, low: Double, conditionName: String, symbol: String,
                precipitationChance: Double, sunrise: Date?, sunset: Date?, unitSymbol: String, fetchedAt: Date) {
        self.temperature = temperature
        self.high = high
        self.low = low
        self.conditionName = conditionName
        self.symbol = symbol
        self.precipitationChance = precipitationChance
        self.sunrise = sunrise
        self.sunset = sunset
        self.unitSymbol = unitSymbol
        self.fetchedAt = fetchedAt
    }
}

/// Cross-feature state. Each property has a single writer (named on it); everyone else only reads.
@MainActor
@Observable
public final class SystemStatus {
    public static let shared = SystemStatus()

    /// Written by NotchSystem's focus monitor.
    public var focus: FocusModeInfo?
    /// Written by NotchLock.
    public var isScreenLocked = false
    /// Written by NotchLock.
    public var isScreenSaverActive = false
    /// Written by NotchMedia; lets other features stay out of the way while music plays.
    public var isMediaPlaying = false
    /// Written by NotchLock's weather manager.
    public var weather: WeatherSnapshot?

    private init() {}
}
