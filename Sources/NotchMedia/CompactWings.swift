import NotchCore
import SwiftUI

struct CompactArtworkWing: View {
    var isPeeking = false
    private let manager = MediaManager.shared
    @AppStorage(MediaSettings.disableArtworkFlip) private var disableFlip

    var body: some View {
        FlippingArtwork(
            image: manager.artwork,
            trackKey: manager.track?.identity ?? "",
            size: 22,
            cornerRadius: 6,
            flips: !disableFlip
        )
        .scaleEffect(manager.isPlaying ? 1 : 0.85)
        .opacity(manager.isPlaying ? 1 : 0.6)
        .animation(.easeInOut(duration: 0.5), value: manager.isPlaying)
        .scaleEffect(isPeeking ? 1.2 : 1, anchor: UnitPoint(x: 0.2, y: 0))
        .animation(.easeInOut(duration: 0.3), value: isPeeking)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompactTrailingWing: View {
    private let manager = MediaManager.shared
    private let status = SystemStatus.shared
    @AppStorage(MediaSettings.disableCompactWaveform) private var disableWaveform
    @AppStorage(MediaSettings.replaceWaveformDuringFocus) private var replaceDuringFocus
    @AppStorage(MediaSettings.colorStyle) private var colorStyle
    @State private var isHovering = false

    var body: some View {
        Group {
            if replaceDuringFocus, let focus = status.focus {
                Image(systemName: focus.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(focus.color)
                    .transition(.scale.combined(with: .opacity))
            } else if !disableWaveform {
                ZStack {
                    IslandWaveform(isPlaying: manager.isPlaying, fill: fill)
                        .scaleEffect(isHovering ? 1.25 : 1)
                        .blur(radius: isHovering ? 3.5 : 0)
                        .brightness(isHovering ? 0.1 : 0)
                    PlayPauseGlyph(symbol: "pause.fill", hidden: !isHovering || !manager.isPlaying)
                    PlayPauseGlyph(symbol: "play.fill", hidden: !isHovering || manager.isPlaying)
                }
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .onHover { hovering in withAnimation(.easeInOut(duration: 0.25)) { isHovering = hovering } }
                .onTapGesture { manager.togglePlayPause() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var fill: AnyShapeStyle {
        if colorStyle == .mono { return AnyShapeStyle(.white) }
        if colorStyle == .color { return AnyShapeStyle(Color.accentColor) }
        if let colors = manager.artworkGradient {
            return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(manager.artworkColor ?? .white)
    }
}

private struct PlayPauseGlyph: View {
    let symbol: String
    let hidden: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .scaleEffect(hidden ? 0.01 : 1)
            .blur(radius: hidden ? 4 : 0)
            .opacity(hidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.4), value: hidden)
    }
}

/// Four 2pt bars pulsing 3 to 12pt at their own tempo; they settle into dots when paused.
struct IslandWaveform: View {
    var isPlaying: Bool
    var fill: AnyShapeStyle

    private static let periods: [Double] = [0.95, 1.46, 0.82, 1.24]
    private let live = LiveWaveform.shared
    @AppStorage(MediaSettings.useLiveWaveform) private var useLiveWaveform

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isPlaying)) { context in
            let heights = currentHeights(at: context.date)
            HStack(spacing: 1.5) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(fill)
                        .frame(width: 2, height: isPlaying ? heights[index] : 2)
                }
            }
            .frame(height: 20)
            .animation(.easeInOut(duration: 0.5), value: isPlaying)
        }
    }

    private func currentHeights(at date: Date) -> [CGFloat] {
        if useLiveWaveform, live.isRunning, live.hasSignal {
            return WaveformView.resample(live.levels, to: 4).map { 3 + 9 * min(max($0, 0), 1) }
        }
        let t = date.timeIntervalSinceReferenceDate
        return Self.periods.map { period in
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let triangle = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let eased = triangle * triangle * (3 - 2 * triangle)
            return 3 + 9 * CGFloat(eased)
        }
    }
}

/// "♪ Title ∙ Artist" scrolling under the camera during a quick peek.
struct PeekBottom: View {
    private let manager = MediaManager.shared

    var body: some View {
        let text = manager.artist.isEmpty ? manager.title : "\(manager.title) ∙ \(manager.artist)"
        HStack(spacing: 3) {
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            MarqueeText(text, font: .system(size: 12, weight: .semibold), speed: 30, pause: 1.2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(white: 0.84).opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
        .padding(.horizontal, 6)
    }
}
