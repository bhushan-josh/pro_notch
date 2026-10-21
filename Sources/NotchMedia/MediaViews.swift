import AppKit
import NotchCore
import SwiftUI

// MARK: Artwork

struct ArtworkTile: View {
    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(.white.opacity(0.12))
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

/// Artwork that turns over like a card when the track changes.
struct FlippingArtwork: View {
    var image: NSImage?
    var trackKey: String
    var size: CGFloat
    var cornerRadius: CGFloat
    var flips: Bool

    @State private var shown: NSImage?
    @State private var shownKey: String?
    @State private var angle: Double = 0
    @State private var didAppear = false

    var body: some View {
        ArtworkTile(image: didAppear ? shown : image, size: size, cornerRadius: cornerRadius)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .onAppear {
                shown = image
                shownKey = trackKey
                didAppear = true
            }
            .onChange(of: image.map(ObjectIdentifier.init)) { update() }
            .onChange(of: trackKey) { update() }
    }

    private func update() {
        guard image !== shown else {
            shownKey = trackKey
            return
        }
        let isNewTrack = trackKey != shownKey
        shownKey = trackKey
        guard flips, isNewTrack else {
            withAnimation(.easeInOut(duration: 0.2)) { shown = image }
            return
        }
        let target = image
        withAnimation(.easeIn(duration: 0.16)) {
            angle = 90
        } completion: {
            shown = target
            angle = -90
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { angle = 0 }
        }
    }
}

// MARK: Closed notch wings

struct CompactArtworkWing: View {
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
    }
}

struct CompactTrailingWing: View {
    private let manager = MediaManager.shared
    private let status = SystemStatus.shared
    @AppStorage(MediaSettings.disableCompactWaveform) private var disableWaveform
    @AppStorage(MediaSettings.replaceWaveformDuringFocus) private var replaceDuringFocus
    @AppStorage(MediaSettings.colorStyle) private var colorStyle

    var body: some View {
        if replaceDuringFocus, let focus = status.focus {
            Image(systemName: focus.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(focus.color)
                .transition(.scale.combined(with: .opacity))
        } else if !disableWaveform {
            WaveformView(
                isPlaying: manager.isPlaying,
                style: MediaTint.shape(colorStyle, artwork: manager.artworkColor),
                barCount: 5,
                barWidth: 2.6,
                spacing: 1.8,
                maxHeight: 13
            )
        }
    }
}

struct PeekBottom: View {
    private let manager = MediaManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            MarqueeText(manager.title, font: .system(size: 12, weight: .semibold))
            if !manager.artist.isEmpty {
                Text(manager.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

// MARK: Progress

struct MediaProgressSlider: View {
    var tint: AnyShapeStyle
    var showsTimes = true
    var barHeight: CGFloat = 5

    private let manager = MediaManager.shared
    @State private var dragFraction: Double?
    @State private var isHovering = false

    var body: some View {
        let track = manager.track
        let duration = track?.duration ?? 0
        let canSeek = duration > 0 && manager.supports(.seek)
        TimelineView(.animation(minimumInterval: 0.25, paused: !(track?.isPlaying ?? false) || dragFraction != nil)) { context in
            let elapsed = dragFraction.map { $0 * duration } ?? (track?.elapsed(at: context.date) ?? 0)
            let fraction = duration > 0 ? elapsed / duration : 0
            VStack(spacing: 3) {
                bar(fraction: fraction, enabled: canSeek, duration: duration)
                if showsTimes {
                    HStack {
                        Text(Self.format(elapsed))
                        Spacer()
                        Text(duration > 0 ? "-" + Self.format(max(0, duration - elapsed)) : "Live")
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private func bar(fraction: Double, enabled: Bool, duration: TimeInterval) -> some View {
        let active = dragFraction != nil || (isHovering && enabled)
        let height = active ? barHeight + 3 : barHeight
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled, proxy.size.width > 0 else { return }
                        dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        guard enabled, let dragFraction else { return }
                        manager.seek(to: dragFraction * duration)
                        self.dragFraction = nil
                    }
            )
        }
        .frame(height: barHeight + 7)
        .onHover { isHovering = $0 }
        .animation(.notchSnappy, value: active)
    }

    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: Controls

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.notchSnappy, value: configuration.isPressed)
    }
}

struct MediaButton: View {
    var symbol: String
    var size: CGFloat = 15
    var isActive = true
    var isEnabled = true
    var help: String?
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            action()
            Haptics.perform()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(isEnabled ? (isActive ? 1 : 0.5) : 0.25))
                .frame(width: size * 2.1, height: size * 2.1)
                .background(Circle().fill(.white.opacity(isHovering && isEnabled ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .help(help ?? "")
    }
}

struct ExtraControlButton: View {
    var control: MediaExtraControl
    var size: CGFloat = 13
    private let manager = MediaManager.shared
    @State private var copied = false

    var body: some View {
        let track = manager.track
        switch control {
        case .none:
            EmptyView()
        case .shuffle:
            MediaButton(symbol: "shuffle", size: size, isActive: track?.shuffle == true,
                        isEnabled: manager.supports(.shuffle), help: "Shuffle") { manager.toggleShuffle() }
        case .repeatMode:
            let mode = track?.repeatMode ?? .off
            MediaButton(symbol: mode == .one ? "repeat.1" : "repeat", size: size, isActive: mode != .off,
                        isEnabled: manager.supports(.repeatMode), help: "Repeat") { manager.cycleRepeat() }
        case .like:
            MediaButton(symbol: track?.liked == true ? "heart.fill" : "heart", size: size,
                        isEnabled: manager.supports(.like), help: "Like") { manager.toggleLike() }
        case .favorite:
            MediaButton(symbol: track?.liked == true ? "star.fill" : "star", size: size,
                        isEnabled: manager.supports(.like), help: "Favorite") { manager.toggleLike() }
        case .copy:
            MediaButton(symbol: copied ? "checkmark" : "link", size: size, isEnabled: track != nil, help: "Copy Link") {
                manager.copyLink()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    copied = false
                }
            }
        }
    }
}

struct TransportControls: View {
    var left: MediaExtraControl = .none
    var right: MediaExtraControl = .none
    var scale: CGFloat = 1
    private let manager = MediaManager.shared

    var body: some View {
        HStack(spacing: 6 * scale) {
            if left != .none { ExtraControlButton(control: left, size: 12 * scale) }
            MediaButton(symbol: "backward.fill", size: 15 * scale, isEnabled: manager.hasMedia, help: "Previous") { manager.previous() }
            MediaButton(symbol: manager.isPlaying ? "pause.fill" : "play.fill", size: 21 * scale, help: manager.isPlaying ? "Pause" : "Play") {
                manager.togglePlayPause()
            }
            MediaButton(symbol: "forward.fill", size: 15 * scale, isEnabled: manager.hasMedia && manager.supports(.skip), help: "Next") { manager.next() }
            if right != .none { ExtraControlButton(control: right, size: 12 * scale) }
        }
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: 11, height: 11)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

// MARK: Home widget

struct NowPlayingWidget: View {
    private let manager = MediaManager.shared
    @AppStorage(MediaSettings.colorStyle) private var colorStyle
    @AppStorage(MediaSettings.leftControl) private var leftControl
    @AppStorage(MediaSettings.rightControl) private var rightControl
    @AppStorage(MediaSettings.disableArtworkFlip) private var disableFlip

    var body: some View {
        Group {
            if manager.hasMedia {
                content
            } else {
                NotPlayingView()
            }
        }
        .contextMenu { MediaContextMenu() }
    }

    private var content: some View {
        let tint = MediaTint.shape(colorStyle, artwork: manager.artworkColor)
        return VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        MarqueeText(manager.title, font: .system(size: 14, weight: .semibold))
                        if manager.track?.isExplicit == true { ExplicitBadge() }
                        WaveformView(isPlaying: manager.isPlaying, style: tint, barCount: 4, barWidth: 2.5, spacing: 1.8, maxHeight: 12)
                    }
                    Text(manager.artist.isEmpty ? manager.album : manager.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    MediaProgressSlider(tint: tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 84)
            }
            TransportControls(left: leftControl, right: rightControl)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            FlippingArtwork(
                image: manager.artwork,
                trackKey: manager.track?.identity ?? "",
                size: 84,
                cornerRadius: 14,
                flips: !disableFlip
            )
            .shadow(color: (manager.artworkColor ?? .clear).opacity(0.35), radius: 14, y: 4)
            if let icon = manager.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(x: 7, y: 7)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { manager.openSourceApp() }
        .help("Open \(manager.sourceAppName)")
    }
}

struct NotPlayingView: View {
    private let manager = MediaManager.shared

    var body: some View {
        let bundleID = manager.preferredAppBundleID
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text("Not Playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Button {
                manager.openPreferredApp()
            } label: {
                HStack(spacing: 6) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text("Open \(manager.sourceAppName)")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MediaContextMenu: View {
    private let manager = MediaManager.shared

    var body: some View {
        if manager.hasMedia {
            Button(manager.isPlaying ? "Pause" : "Play") { manager.togglePlayPause() }
            Button("Next Track") { manager.next() }
            Button("Previous Track") { manager.previous() }
            Divider()
            Button("Copy Link") { manager.copyLink() }
            Button("Show in \(manager.sourceAppName)") { manager.showInApp() }
        } else {
            Button("Open \(manager.sourceAppName)") { manager.openPreferredApp() }
        }
    }
}
