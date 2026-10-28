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
    /// The image most recently handed to `shown`, possibly still mid-flip.
    @State private var latest: NSImage?
    @State private var shownKey: String?
    /// Set on a track change; the old art stays until the new track's art lands, which then flips in.
    @State private var awaitingArt = false
    @State private var angle: Double = 0
    @State private var didAppear = false

    var body: some View {
        ArtworkTile(image: didAppear ? shown : image, size: size, cornerRadius: cornerRadius)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .onAppear {
                shown = image
                latest = image
                shownKey = trackKey
                didAppear = true
            }
            .onChange(of: image.map(ObjectIdentifier.init)) { update() }
            .onChange(of: trackKey) { update() }
    }

    private func update() {
        if trackKey != shownKey {
            shownKey = trackKey
            awaitingArt = flips
        }
        guard image !== latest else { return }
        latest = image
        let target = image
        guard awaitingArt else {
            withAnimation(.easeInOut(duration: 0.2)) { shown = target }
            return
        }
        awaitingArt = false
        withAnimation(.easeIn(duration: 0.16)) {
            angle = 90
        } completion: {
            shown = latest
            angle = -90
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { angle = 0 }
        }
    }
}

// MARK: Progress

struct MediaProgressSlider: View {
    var tint: AnyShapeStyle
    var timeColor: Color = .white.opacity(0.5)
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
            HStack(spacing: 8) {
                if showsTimes {
                    Text(duration > 0 ? Self.format(elapsed) : "-:--").frame(minWidth: 26, alignment: .leading)
                }
                bar(fraction: fraction, enabled: canSeek, duration: duration)
                if showsTimes {
                    Text(duration > 0 ? "-" + Self.format(max(0, duration - elapsed)) : "Live").frame(minWidth: 26, alignment: .trailing)
                }
            }
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(timeColor)
        }
    }

    private func bar(fraction: Double, enabled: Bool, duration: TimeInterval) -> some View {
        let active = dragFraction != nil || (isHovering && enabled)
        let height = active ? barHeight + 3 : barHeight
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
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
                .foregroundStyle(.white.opacity(isEnabled ? (isActive ? 0.95 : 0.45) : 0.25))
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(isHovering && isEnabled ? 0.1 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            if left != .none { ExtraControlButton(control: left, size: 16 * scale) }
            MediaButton(symbol: "backward.fill", size: 19 * scale, isEnabled: manager.hasMedia, help: "Previous") { manager.previous() }
            MediaButton(symbol: manager.isPlaying ? "pause.fill" : "play.fill", size: 25 * scale, help: manager.isPlaying ? "Pause" : "Play") {
                manager.togglePlayPause()
            }
            MediaButton(symbol: "forward.fill", size: 19 * scale, isEnabled: manager.hasMedia && manager.supports(.skip), help: "Next") { manager.next() }
            if right != .none { ExtraControlButton(control: right, size: 16 * scale) }
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
    @AppStorage(MediaSettings.showIdleClock) private var showIdleClock
    @AppStorage(MediaSettings.colorStyle) private var colorStyle
    @AppStorage(MediaSettings.leftControl) private var leftControl
    @AppStorage(MediaSettings.rightControl) private var rightControl
    @AppStorage(MediaSettings.disableArtworkFlip) private var disableFlip
    private let lyricsManager = LyricsManager.shared
    @State private var showsLyrics = false

    var body: some View {
        Group {
            if manager.hasMedia {
                if showsLyrics, let lyrics = lyricsManager.lyrics {
                    LyricsScrollView(lyrics: lyrics) { withAnimation(.notchSnappy) { showsLyrics = false } }
                        .transition(.opacity)
                } else {
                    content
                        .transition(.opacity)
                }
            } else if showIdleClock {
                IdleClockView()
                    .transition(.opacity)
            } else {
                NotPlayingView()
            }
        }
        .animation(.notchSnappy, value: manager.hasMedia)
        .contextMenu { MediaContextMenu() }
        .onChange(of: manager.track?.identity) { showsLyrics = false }
    }

    private var content: some View {
        let tint = MediaTint.shape(colorStyle, artwork: manager.artworkColor)
        let secondary = (manager.artworkColor ?? .white).opacity(0.75)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                artwork
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        MarqueeText(manager.title, font: .system(size: 13.5, weight: .semibold))
                        if manager.track?.isExplicit == true { ExplicitBadge() }
                    }
                    Text(manager.artist.isEmpty ? manager.album : manager.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                    if let lyrics = lyricsManager.lyrics {
                        WidgetLyricLine(lyrics: lyrics, color: .white.opacity(0.9)) {
                            withAnimation(.notchSnappy) { showsLyrics = true }
                        }
                        .padding(.top, 2)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: lyricsManager.lyrics != nil)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                IslandWaveform(isPlaying: manager.isPlaying, fill: tint)
                    .frame(width: 20)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
            }
            MediaProgressSlider(tint: tint, timeColor: secondary, barHeight: 6)
                .padding(.top, 14)
            Spacer(minLength: 2)
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
                size: 56,
                cornerRadius: 12,
                flips: !disableFlip
            )
            .opacity(0.95)
            .scaleEffect(manager.isPlaying ? 1 : 0.92)
            .animation(.easeInOut(duration: 0.5), value: manager.isPlaying)
            if let icon = manager.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: 5, y: 5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { manager.openSourceApp() }
        .help("Open \(manager.sourceAppName)")
    }
}

/// The player with nothing loaded: placeholder artwork, empty progress and dimmed controls, no app launching.
struct NotPlayingView: View {
    var body: some View {
        let dim = Color.white.opacity(0.4)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.1))
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(width: 56, height: 56)
                Text("Not Playing")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 1.5) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.25)).frame(width: 2, height: 2)
                    }
                }
                .frame(width: 20)
                .padding(.leading, 8)
                .padding(.trailing, 4)
            }
            HStack(spacing: 8) {
                Text("-:--").frame(minWidth: 26, alignment: .leading)
                Capsule().fill(.white.opacity(0.15)).frame(height: 6)
                Text("-:--").frame(minWidth: 26, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(dim)
            .padding(.top, 14)
            Spacer(minLength: 2)
            HStack(spacing: 6) {
                MediaButton(symbol: "backward.fill", size: 19, isEnabled: false) {}
                MediaButton(symbol: "play.fill", size: 25, isEnabled: false) {}
                MediaButton(symbol: "forward.fill", size: 19, isEnabled: false) {}
            }
            .frame(maxWidth: .infinity)
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
        }
    }
}
