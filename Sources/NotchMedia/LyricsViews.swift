import NotchCore
import SwiftUI

/// Re-evaluates `content` four times a second while the track plays; holds still while paused.
struct LyricsClock<Content: View>: View {
    var isPlaying: Bool
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if isPlaying {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in content(context.date) }
        } else {
            content(Date())
        }
    }
}

/// One lyric line that crossfades whenever `index` moves on.
struct LyricLineText: View {
    var text: String
    var index: Int
    var font: Font
    var alignment: Alignment = .leading

    var body: some View {
        ZStack(alignment: alignment) {
            Text(text.isEmpty ? "♪" : text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .opacity(text.isEmpty ? 0.5 : 1)
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .offset(y: -4))
                ))
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .animation(.easeInOut(duration: 0.35), value: index)
    }
}

/// The current line under the artist in the Now Playing widget; tapping opens the full lyrics.
struct WidgetLyricLine: View {
    var lyrics: Lyrics
    var color: Color
    var onOpen: () -> Void

    private let manager = MediaManager.shared
    private let lyricsManager = LyricsManager.shared

    var body: some View {
        Group {
            if lyrics.isSynced, let track = manager.track {
                LyricsClock(isPlaying: track.isPlaying) { date in
                    let index = lyricsManager.lineIndex(in: lyrics, track: track, at: date)
                    LyricLineText(text: index.map { lyrics.lines[$0].text } ?? "", index: index ?? -1, font: .system(size: 11.5, weight: .semibold))
                }
            } else {
                Label("Lyrics", systemImage: "quote.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(color)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .help("Show Lyrics")
    }
}

/// Scrolling lyrics inside the Now Playing widget, following the song when they are synced.
struct LyricsScrollView: View {
    var lyrics: Lyrics
    var onClose: () -> Void

    private let manager = MediaManager.shared
    private let lyricsManager = LyricsManager.shared
    @State private var current: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 5) {
                    if lyrics.isSynced {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            row(line.text.isEmpty ? "♪" : line.text, highlighted: index == current)
                                .id(index)
                                .onTapGesture { seek(to: line) }
                        }
                    } else {
                        ForEach(Array(lyrics.plain.enumerated()), id: \.offset) { _, text in
                            row(text.isEmpty ? " " : text, highlighted: true)
                        }
                    }
                }
                .padding(.vertical, 40)
                .padding(.trailing, 22)
            }
            .scrollIndicators(.never)
            .mask(LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            ))
            .background {
                if lyrics.isSynced, let track = manager.track {
                    LyricsClock(isPlaying: track.isPlaying) { date in
                        Color.clear.onChange(of: lyricsManager.lineIndex(in: lyrics, track: track, at: date), initial: true) { _, index in
                            current = index
                        }
                    }
                }
            }
            .onChange(of: current) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(PressScaleStyle())
            .help("Hide Lyrics")
        }
    }

    private func row(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(highlighted ? 0.95 : 0.35))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.3), value: highlighted)
    }

    private func seek(to line: Lyrics.Line) {
        guard manager.supports(.seek) else { return }
        manager.seek(to: line.time + lyricsManager.offset)
    }
}

/// The current line in a strip below the closed notch.
struct LyricsStrip: View {
    private let manager = MediaManager.shared
    private let lyricsManager = LyricsManager.shared

    var body: some View {
        Group {
            if let track = manager.track, let lyrics = lyricsManager.lyrics, lyrics.isSynced {
                LyricsClock(isPlaying: track.isPlaying) { date in
                    let index = lyricsManager.lineIndex(in: lyrics, track: track, at: date)
                    LyricLineText(text: index.map { lyrics.lines[$0].text } ?? "", index: index ?? -1, font: .system(size: 12, weight: .semibold), alignment: .center)
                }
            }
        }
        .foregroundStyle(Color(white: 0.84).opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 7)
        .padding(.horizontal, 10)
    }
}
