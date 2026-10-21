import NotchCore
import Observation
import SwiftUI

/// System output volume through Standard Additions, polled only while a view that shows it is on screen.
@MainActor
@Observable
final class SystemVolume {
    static let shared = SystemVolume()

    private(set) var level: Double = 0.5
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSet: Task<Void, Never>?
    @ObservationIgnored private var lastLocalChange = Date.distantPast

    private init() {}

    func attach() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.read()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func set(_ value: Double) {
        level = min(max(value, 0), 1)
        lastLocalChange = Date()
        pendingSet?.cancel()
        let percent = Int((level * 100).rounded())
        pendingSet = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            _ = try? await AppleScriptRunner.run("set volume output volume \(percent)")
        }
    }

    private func read() async {
        guard Date().timeIntervalSince(lastLocalChange) > 1,
              let result = await AppleScriptRunner.string("output volume of (get volume settings)"),
              let value = Double(result) else { return }
        let normalized = value / 100
        if abs(normalized - level) > 0.005 { level = normalized }
    }
}

struct LockScreenMediaView: View {
    private let manager = MediaManager.shared
    private let volume = SystemVolume.shared
    @AppStorage(MediaSettings.colorStyle) private var colorStyle
    @AppStorage(MediaSettings.lockScreenVolumeControl) private var showVolume

    var body: some View {
        let tint = MediaTint.shape(colorStyle, artwork: manager.artworkColor)
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                FlippingArtwork(image: manager.artwork, trackKey: manager.track?.identity ?? "", size: 54, cornerRadius: 10, flips: true)
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(manager.title, font: .system(size: 14, weight: .semibold))
                    Text(manager.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WaveformView(isPlaying: manager.isPlaying, style: tint, barCount: 5, barWidth: 3, spacing: 2, maxHeight: 16)
            }
            MediaProgressSlider(tint: tint, barHeight: 4)
            TransportControls(scale: 1.05)
            if showVolume {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    VolumeBar(level: volume.level, tint: tint) { volume.set($0) }
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .onAppear { volume.attach() }
                .onDisappear { volume.detach() }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 340)
        .background(Color.clear)
    }
}

private struct VolumeBar: View {
    var level: Double
    var tint: AnyShapeStyle
    var onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(tint).frame(width: max(6, proxy.size.width * level))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard proxy.size.width > 0 else { return }
                onChange(min(max(value.location.x / proxy.size.width, 0), 1))
            })
        }
        .frame(height: 14)
    }
}
