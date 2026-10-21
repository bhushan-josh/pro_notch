import Foundation

/// WMO weather interpretation codes as returned by Open-Meteo.
enum WeatherCode {
    struct Condition {
        let name: String
        let daySymbol: String
        let nightSymbol: String

        init(_ name: String, _ daySymbol: String, _ nightSymbol: String? = nil) {
            self.name = name
            self.daySymbol = daySymbol
            self.nightSymbol = nightSymbol ?? daySymbol
        }

        func symbol(isDay: Bool) -> String { isDay ? daySymbol : nightSymbol }
    }

    static func condition(for code: Int) -> Condition {
        switch code {
        case 0: Condition("Clear", "sun.max.fill", "moon.stars.fill")
        case 1: Condition("Mostly Clear", "sun.max.fill", "moon.fill")
        case 2: Condition("Partly Cloudy", "cloud.sun.fill", "cloud.moon.fill")
        case 3: Condition("Cloudy", "cloud.fill")
        case 45, 48: Condition("Fog", "cloud.fog.fill")
        case 51, 53: Condition("Drizzle", "cloud.drizzle.fill")
        case 55: Condition("Heavy Drizzle", "cloud.drizzle.fill")
        case 56, 57: Condition("Freezing Drizzle", "cloud.sleet.fill")
        case 61: Condition("Light Rain", "cloud.rain.fill")
        case 63: Condition("Rain", "cloud.rain.fill")
        case 65: Condition("Heavy Rain", "cloud.heavyrain.fill")
        case 66, 67: Condition("Freezing Rain", "cloud.sleet.fill")
        case 71: Condition("Light Snow", "cloud.snow.fill")
        case 73: Condition("Snow", "cloud.snow.fill")
        case 75: Condition("Heavy Snow", "snowflake")
        case 77: Condition("Snow Grains", "cloud.snow.fill")
        case 80, 81: Condition("Rain Showers", "cloud.sun.rain.fill", "cloud.moon.rain.fill")
        case 82: Condition("Heavy Showers", "cloud.heavyrain.fill")
        case 85, 86: Condition("Snow Showers", "cloud.snow.fill")
        case 95: Condition("Thunderstorms", "cloud.bolt.rain.fill")
        case 96, 99: Condition("Thunderstorms with Hail", "cloud.bolt.rain.fill")
        default: Condition("Unknown", "questionmark.circle")
        }
    }
}
