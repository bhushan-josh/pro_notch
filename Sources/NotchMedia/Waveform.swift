import NotchCore
import SwiftUI

enum MediaTint {
    @MainActor
    static func color(_ style: MediaColorStyle, artwork: Color?) -> Color {
        switch style {
        case .artwork, .gradient: artwork ?? .white
        case .color: .accentColor
        case .mono: .white
        }
    }

    @MainActor
    static func shape(_ style: MediaColorStyle, artwork: Color?) -> AnyShapeStyle {
        switch style {
        case .gradient:
            let base = artwork ?? .white
            return AnyShapeStyle(LinearGradient(colors: [base, base.mix(with: .white, by: 0.5)], startPoint: .leading, endPoint: .trailing))
        default:
            return AnyShapeStyle(color(style, artwork: artwork))
        }
    }
}

/// Rounded bars that bounce while playing: live levels from the audio tap when available, a simulation otherwise.
struct WaveformView: View {
    var isPlaying: Bool
    var style: AnyShapeStyle
    var barCount = 5
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var maxHeight: CGFloat = 14

    @AppStorage(MediaSettings.useLiveWaveform) private var useLiveWaveform
    private let live = LiveWaveform.shared

    var body: some View {
        Group {
            if isPlaying, useLiveWaveform, live.isRunning, live.hasSignal {
                bars(Self.resample(live.levels, to: barCount))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { context in
                    bars(isPlaying ? Self.simulated(at: context.date, count: barCount) : flat)
                }
            }
        }
        .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing, height: maxHeight)
        .animation(.easeOut(duration: 0.35), value: isPlaying)
    }

    private var flat: [CGFloat] { Array(repeating: 0, count: barCount) }

    private func bars(_ levels: [CGFloat]) -> some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? levels[index] : 0
                Capsule()
                    .fill(style)
                    .frame(width: barWidth, height: max(barWidth, maxHeight * min(max(level, 0), 1)))
            }
        }
    }

    private static let phases: [Double] = [0.0, 1.7, 3.1, 0.9, 2.4, 4.2]
    private static let speeds: [Double] = [5.1, 6.7, 4.3, 7.4, 5.8, 6.1]

    static func simulated(at date: Date, count: Int) -> [CGFloat] {
        let t = date.timeIntervalSinceReferenceDate
        return (0..<count).map { index in
            let phase = phases[index % phases.count]
            let speed = speeds[index % speeds.count]
            let primary = abs(sin(t * speed + phase))
            let secondary = abs(sin(t * speed * 0.53 + phase * 1.9))
            return CGFloat(0.25 + 0.75 * (primary * 0.65 + secondary * 0.35))
        }
    }

    static func resample(_ levels: [CGFloat], to count: Int) -> [CGFloat] {
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        guard levels.count != count, count > 1 else { return levels }
        return (0..<count).map { index in
            let position = Double(index) * Double(levels.count - 1) / Double(count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, levels.count - 1)
            let fraction = CGFloat(position - Double(lower))
            return levels[lower] * (1 - fraction) + levels[upper] * fraction
        }
    }
}
