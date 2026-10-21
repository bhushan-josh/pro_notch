import AppKit
import NotchCore

@MainActor
final class MusicBackend: PollingBackend {
    static let bundleID = "com.apple.Music"

    init() { super.init(kind: .music) }

    override var capabilities: Set<MediaCapability> { [.skip, .seek, .shuffle, .repeatMode, .like] }
    override var notificationNames: [String] { ["com.apple.Music.playerInfo"] }
    override var watchedBundleIDs: [String] { [Self.bundleID] }

    private static let stateScript = """
    if application id "com.apple.Music" is running then
        tell application id "com.apple.Music"
            set playerState to player state as string
            if playerState is "stopped" then return {playerState}
            set theTrack to current track
            set isFavorite to missing value
            try
                set isFavorite to favorited of theTrack
            on error
                try
                    set isFavorite to loved of theTrack
                end try
            end try
            set isShuffled to false
            try
                set isShuffled to shuffle enabled
            end try
            set repeatValue to "off"
            try
                set repeatValue to song repeat as string
            end try
            return {playerState, name of theTrack, artist of theTrack, album of theTrack, duration of theTrack, player position, isShuffled, repeatValue, isFavorite}
        end tell
    end if
    return {"stopped"}
    """

    override func poll() async {
        guard AppleScriptRunner.isRunning(bundleID: Self.bundleID) else {
            publish(nil)
            return
        }
        guard let result = await runStateScript(Self.stateScript) else { return }
        let state = result.string(1)
        guard state == "playing" || state == "paused" || state.hasPrefix("fast") || state.hasPrefix("rewind") else {
            publish(nil)
            return
        }
        var track = TrackSnapshot()
        track.bundleID = Self.bundleID
        track.isPlaying = state == "playing"
        track.title = result.string(2)
        track.artist = result.string(3)
        track.album = result.string(4)
        track.duration = result.double(5)
        track.elapsed = result.double(6)
        track.timestamp = Date()
        track.shuffle = result.bool(7) ?? false
        track.repeatMode = RepeatMode(rawValue: result.string(8)) ?? .off
        track.liked = result.bool(9)
        publish(track)
    }

    override func artwork(for track: TrackSnapshot) async -> NSImage? {
        let script = """
        if application id "com.apple.Music" is running then
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
                try
                    return data of artwork 1 of current track
                end try
            end tell
        end if
        return missing value
        """
        guard let descriptor = try? await AppleScriptRunner.run(script) else { return nil }
        let data = descriptor.data
        guard !data.isEmpty, let image = NSImage(data: data), image.isValid else { return nil }
        return image
    }

    override func send(_ command: MediaCommand) {
        guard AppleScriptRunner.isRunning(bundleID: Self.bundleID) else { return }
        let body: String
        switch command {
        case .togglePlayPause:
            body = "playpause"
            optimistic { $0.isPlaying.toggle() }
        case .play:
            body = "play"
            optimistic { $0.isPlaying = true }
        case .pause:
            body = "pause"
            optimistic { $0.isPlaying = false }
        case .next:
            body = "next track"
        case .previous:
            body = "previous track"
        case .seek(let position):
            body = "set player position to \(position)"
            optimistic { $0.elapsed = position }
        case .setShuffle(let on):
            body = "set shuffle enabled to \(on)"
            optimistic { $0.shuffle = on }
        case .setRepeat(let mode):
            body = "set song repeat to \(mode.rawValue)"
            optimistic { $0.repeatMode = mode }
        case .setLiked(let liked):
            body = """
            try
                set favorited of current track to \(liked)
            on error
                set loved of current track to \(liked)
            end try
            """
            optimistic { $0.liked = liked }
        }
        let script = """
        if application id "com.apple.Music" is running then
            tell application id "com.apple.Music"
                \(body)
            end tell
        end if
        """
        Task {
            _ = try? await AppleScriptRunner.run(script)
            refreshSoon()
        }
    }

    func revealCurrentTrack() {
        Task {
            _ = try? await AppleScriptRunner.run("""
            if application id "com.apple.Music" is running then
                tell application id "com.apple.Music"
                    try
                        reveal current track
                    end try
                    activate
                end tell
            end if
            """)
        }
    }
}
