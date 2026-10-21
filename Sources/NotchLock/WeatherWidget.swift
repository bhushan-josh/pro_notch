import SwiftUI
import NotchCore

enum WeatherWidget {
    static let id = "weather"

    @MainActor
    static func make() -> LockScreenWidget {
        LockScreenWidget(id: id, order: 10) { WeatherWidgetView() }
    }

    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

struct WeatherWidgetView: View {
    @AppStorage(LockSettings.weatherStyle) private var style
    private let status = SystemStatus.shared

    var body: some View {
        if let weather = status.weather {
            Group {
                switch style {
                case .conditions: WeatherConditionsView(weather: weather)
                case .precipitation: WeatherPrecipitationView(weather: weather)
                case .sun: WeatherSunView(weather: weather)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WeatherConditionsView: View {
    let weather: WeatherSnapshot

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 34))
                .frame(width: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(WeatherWidget.temperature(weather.temperature))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(weather.conditionName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Label(WeatherWidget.temperature(weather.high), systemImage: "arrow.up")
                Label(WeatherWidget.temperature(weather.low), systemImage: "arrow.down")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .labelStyle(CompactLabelStyle())
        }
    }
}

private struct WeatherPrecipitationView: View {
    let weather: WeatherSnapshot

    private var chance: Double { min(max(weather.precipitationChance, 0), 1) }

    private var summary: String {
        switch chance {
        case ..<0.15: "Rain is unlikely today"
        case ..<0.4: "A slight chance of rain today"
        case ..<0.7: "Rain is possible today"
        default: "Rain is likely today"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Chance of Rain", systemImage: chance >= 0.4 ? "umbrella.fill" : "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(Int((chance * 100).rounded()))%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(proxy.size.height, proxy.size.width * chance))
                    }
            }
            .frame(height: 8)
            HStack {
                Text(summary)
                Spacer()
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor)
                Text(WeatherWidget.temperature(weather.temperature))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
        }
    }
}

private struct WeatherSunView: View {
    let weather: WeatherSnapshot

    var body: some View {
        TimelineView(.everyMinute) { context in
            let progress = sunProgress(at: context.date)
            VStack(spacing: 8) {
                SunArc(progress: progress)
                    .frame(height: 64)
                HStack {
                    sunTime("sunrise.fill", weather.sunrise)
                    Spacer()
                    Text(headline(at: context.date, progress: progress))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    sunTime("sunset.fill", weather.sunset)
                }
            }
        }
    }

    @ViewBuilder
    private func sunTime(_ symbol: String, _ date: Date?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
            if let date {
                Text(date, format: .dateTime.hour().minute())
            } else {
                Text("--")
            }
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }

    private func sunProgress(at date: Date) -> Double? {
        guard let sunrise = weather.sunrise, let sunset = weather.sunset, sunset > sunrise,
              date >= sunrise, date <= sunset else { return nil }
        return date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
    }

    private func headline(at date: Date, progress: Double?) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        if progress != nil, let sunset = weather.sunset {
            return "Sunset in " + (formatter.string(from: sunset.timeIntervalSince(date)) ?? "")
        }
        if let sunrise = weather.sunrise, sunrise > date {
            return "Sunrise in " + (formatter.string(from: sunrise.timeIntervalSince(date)) ?? "")
        }
        return "After sunset"
    }
}

private struct SunArc: View {
    let progress: Double?

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 2)
            let radiusX = size.width / 2 - 10
            let radiusY = size.height - 10

            func point(_ t: Double) -> CGPoint {
                let angle = Double.pi * (1 - t)
                return CGPoint(x: center.x + radiusX * cos(angle), y: center.y - radiusY * sin(angle))
            }

            func arc(to end: Double) -> Path {
                var path = Path()
                let steps = 64
                for step in 0...steps {
                    let p = point(end * Double(step) / Double(steps))
                    step == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                return path
            }

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: center.y))
            horizon.addLine(to: CGPoint(x: size.width, y: center.y))
            context.stroke(horizon, with: .color(.white.opacity(0.18)), lineWidth: 1)
            context.stroke(arc(to: 1), with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))

            guard let progress else { return }
            context.stroke(arc(to: progress), with: .color(.yellow.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let sun = point(progress)
            let glow = CGRect(x: sun.x - 10, y: sun.y - 10, width: 20, height: 20)
            context.fill(Path(ellipseIn: glow), with: .color(.yellow.opacity(0.25)))
            let disc = CGRect(x: sun.x - 5, y: sun.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: disc), with: .color(.yellow))
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10, weight: .bold))
            configuration.title
        }
    }
}
