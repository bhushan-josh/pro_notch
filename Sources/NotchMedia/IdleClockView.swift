import NotchCore
import SwiftUI

/// Shown in place of the player while nothing is loaded: time, date, weather and the next event.
struct IdleClockView: View {
    private let status = SystemStatus.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(now, format: .dateTime.hour().minute().second())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.notchSnappy, value: now)
                    Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .minimumScaleFactor(0.8)
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                HStack(alignment: .center, spacing: 10) {
                    if let event = status.nextEvent, event.end > now {
                        IdleEventRow(event: event, now: now)
                    } else {
                        Label("Nothing playing", systemImage: "music.note")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let weather = status.weather {
                        IdleWeather(weather: weather)
                    }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct IdleWeather: View {
    let weather: WeatherSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 18))
            VStack(alignment: .trailing, spacing: 0) {
                Text(Self.degrees(weather.temperature))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("H:\(Self.degrees(weather.high)) L:\(Self.degrees(weather.low))")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .monospacedDigit()
        }
        .fixedSize()
        .help(weather.conditionName)
    }

    private static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}

private struct IdleEventRow: View {
    let event: UpcomingEventInfo
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(event.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title.isEmpty ? "Event" : event.title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(timing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
        }
    }

    private var timing: String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        if event.start <= now { return "Now · until \(event.end.formatted(time))" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "Next · in \(minutes) min" }
        if Calendar.current.isDateInToday(event.start) { return "Next · \(event.start.formatted(time))" }
        return "Tomorrow · \(event.start.formatted(time))"
    }
}
