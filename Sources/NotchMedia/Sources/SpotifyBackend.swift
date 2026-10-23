import AppKit
import NotchCore

@MainActor
final class SpotifyBackend: PollingBackend {
    static let bundleID = "com.spotify.client"

    init() { super.init(kind: .spotify) }

    override var capabilities: Set<MediaCapability> { [.skip, .seek, .shuffle, .repeatMode] }
    override var notificationNames: [String] { ["com.spotify.client.PlaybackStateChanged"] }
    override var watchedBundleIDs: [String] { [Self.bundleID] }

    private static let stateScript = """
    if application id "com.spotify.client" is running then
        tell application id "com.spotify.client"
            set playerState to player state as string
            if playerState is "stopped" then return {playerState}
            set theTrack to current track
            set artURL to ""
            try
                set artURL to artwork url of theTrack
            end try
            set trackLink to ""
            try
                set trackLink to spotify url of theTrack
            end try
            return {playerState, name of theTrack, artist of theTrack, album of theTrack, duration of theTrack, player position, shuffling, repeating, artURL, trackLink}
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
        guard state == "playing" || state == "paused" else {
            publish(nil)
            return
        }
        var track = TrackSnapshot()
        track.bundleID = Self.bundleID
        track.isPlaying = state == "playing"
        track.title = result.string(2)
        track.artist = result.string(3)
        track.album = result.string(4)
        track.duration = result.double(5) / 1000
        track.elapsed = result.double(6)
        track.timestamp = Date()
        track.shuffle = result.bool(7) ?? false
        let repeating = result.bool(8) ?? false
        track.repeatMode = repeating ? .all : .off
        let art = result.string(9)
        if !art.isEmpty { track.artworkURL = URL(string: art) }
        track.link = Self.webLink(for: result.string(10))
        publish(track)
    }

    /// `spotify:track:ID` to `https://open.spotify.com/track/ID`, which is what people expect to paste.
    static func webLink(for uri: String) -> URL? {
        let parts = uri.split(separator: ":")
        guard parts.count >= 3, parts[0] == "spotify" else { return URL(string: uri) }
        return URL(string: "https://open.spotify.com/" + parts.dropFirst().joined(separator: "/"))
    }

    override func send(_ command: MediaCommand) {
        guard AppleScriptRunner.isRunning(bundleID: Self.bundleID) else { return }
        let body: String
        switch command {
        case .togglePlayPause:
            body = "playpause"
            optimistic { $0.isPlaying.toggle() }
        case .next:
            body = "next track"
        case .previous:
            body = "previous track"
        case .seek(let position):
            body = "set player position to \(position)"
            optimistic { $0.elapsed = position }
        case .setShuffle(let on):
            body = "set shuffling to \(on)"
            optimistic { $0.shuffle = on }
        case .setRepeat(let mode):
            let on = mode != .off
            body = "set repeating to \(on)"
            optimistic { $0.repeatMode = on ? .all : .off }
        case .setLiked:
            return
        }
        let script = """
        if application id "com.spotify.client" is running then
            tell application id "com.spotify.client"
                \(body)
            end tell
        end if
        """
        Task {
            _ = try? await AppleScriptRunner.run(script)
            refreshSoon()
        }
    }
}
