import AppKit
import NotchCore
import Observation
import SwiftUI

/// The single source of now-playing truth. Owns every backend and exposes whichever one is current.
@MainActor
@Observable
public final class MediaManager {
    public static let shared = MediaManager()

    private(set) var track: TrackSnapshot?
    private(set) var sourceKind: MediaSourceKind?
    private(set) var capabilities: Set<MediaCapability> = []
    private(set) var artwork: NSImage?
    private(set) var artworkColor: Color?
    /// Two colors sampled from the artwork's top and bottom halves.
    private(set) var artworkGradient: [Color]?
    private(set) var appIcon: NSImage?
    /// Bumps on every meaningful change; feeds the idle provider's "most recent" ordering.
    private(set) var lastChangeAt = Date()
    /// The paused activity has outlived `nowPlaying.idleDuration`.
    private(set) var pauseExpired = false
    private(set) var frontmostBundleID: String?
    /// Changes whenever any nowPlaying setting changes, so computed properties that read Defaults re-evaluate.
    private(set) var settingsRevision = 0

    @ObservationIgnored var onTrackChange: (@MainActor (TrackSnapshot) -> Void)?
    @ObservationIgnored var onHasMediaChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored let music = MusicBackend()
    @ObservationIgnored let spotify = SpotifyBackend()
    @ObservationIgnored let system = MediaRemoteBackend()
    @ObservationIgnored let browser = BrowserBackend()
    @ObservationIgnored private var active: MediaBackend?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var settingsObserver: SettingsWatcher?
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var artworkKey: String?
    @ObservationIgnored private var artworkCache: [String: (image: NSImage, color: Color?, gradient: [Color]?)] = [:]
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var lastIdentity: String?
    @ObservationIgnored private var lastPlaying = false
    @ObservationIgnored private var lastUsedBundleID: String?

    private var backends: [MediaBackend] { [music, spotify, system, browser] }

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        for backend in backends {
            backend.onChange = { [weak self] in self?.reselect() }
        }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.frontmostBundleID = bundleID }
        }
        settingsObserver = SettingsWatcher(MediaSettings.allNames) { [weak self] in
            guard let self else { return }
            self.settingsRevision += 1
            self.pauseTask?.cancel()
            self.pauseTask = nil
            self.pauseExpired = false
            self.configureBackends()
            self.reselect()
            self.updateLiveWaveform()
        }
        configureBackends()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        settingsObserver = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        backends.forEach { if $0.isRunning { $0.stop() } }
        pauseTask?.cancel()
        artworkTask?.cancel()
        LiveWaveform.shared.setWanted(false)
        reselect()
    }

    private func configureBackends() {
        let source = Defaults[MediaSettings.mediaSource]
        let wanted: Set<MediaSourceKind> = switch source {
        case .automatic: [.music, .spotify, .system]
        case .music: [.music]
        case .spotify: [.spotify]
        // Music and Spotify stay on as a fallback for when the system service withholds now-playing info.
        case .system: [.system, .music, .spotify]
        default: [.browser]
        }
        browser.allowed = source.browser.map { [$0] }
        let browserWanted = Defaults[MediaSettings.browserSource]
        for backend in backends {
            let shouldRun = backend.kind == .browser
                ? (source.isBrowserSource || (source == .automatic && browserWanted))
                : wanted.contains(backend.kind)
            if shouldRun, !backend.isRunning {
                backend.start()
            } else if !shouldRun, backend.isRunning {
                backend.stop()
            }
        }
    }

    // MARK: Selection

    private func candidates() -> [MediaBackend] {
        var running = backends.filter { $0.isRunning && $0.snapshot != nil }
        if Defaults[MediaSettings.mediaSource] == .system, system.isDelivering {
            running.removeAll { $0.kind == .music || $0.kind == .spotify }
        }
        let dedicated = Set(running.filter { $0.kind != .system }.compactMap { $0.snapshot?.bundleID })
        // The system source mirrors Music and Spotify too; the scripted backends know more, so they win.
        return running.filter { backend in
            guard backend.kind == .system, let bundleID = backend.snapshot?.bundleID else { return true }
            return !dedicated.contains(bundleID)
        }
    }

    private func pick() -> MediaBackend? {
        candidates().max { lhs, rhs in
            let l = (lhs.snapshot?.isPlaying == true ? 1 : 0, lhs.lastActiveAt)
            let r = (rhs.snapshot?.isPlaying == true ? 1 : 0, rhs.lastActiveAt)
            return l < r
        }
    }

    private func reselect() {
        let backend = isStarted ? pick() : nil
        let new = backend?.snapshot
        let hadMedia = track != nil
        active = backend
        sourceKind = backend?.kind
        capabilities = backend?.capabilities ?? []
        if track != new { track = new }

        let identity = new?.identity
        if identity != lastIdentity {
            let previous = lastIdentity
            lastIdentity = identity
            lastChangeAt = Date()
            updateAppIcon(bundleID: new?.bundleID)
            if let new, let backend {
                lastUsedBundleID = new.bundleID ?? lastUsedBundleID
                loadArtwork(for: new, from: backend)
                if previous != nil || new.isPlaying { onTrackChange?(new) }
            } else {
                artworkTask?.cancel()
                artworkKey = nil
                artwork = nil
                artworkColor = nil
                artworkGradient = nil
            }
        } else if let new, let backend {
            loadArtwork(for: new, from: backend)
        }

        let playing = new?.isPlaying ?? false
        if playing != lastPlaying {
            lastPlaying = playing
            lastChangeAt = Date()
        }
        updatePauseTimer(playing: playing, hasMedia: new != nil)
        if SystemStatus.shared.isMediaPlaying != playing { SystemStatus.shared.isMediaPlaying = playing }
        if hadMedia != (new != nil) { onHasMediaChange?(new != nil) }
        updateLiveWaveform()
    }

    private func updatePauseTimer(playing: Bool, hasMedia: Bool) {
        if playing || !hasMedia {
            pauseTask?.cancel()
            pauseTask = nil
            if pauseExpired { pauseExpired = false }
            return
        }
        guard pauseTask == nil, !pauseExpired else { return }
        let duration = Defaults[MediaSettings.idleDuration]
        guard duration > 0 else { return }
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.track?.isPlaying == false else { return }
            self.pauseExpired = true
            self.lastChangeAt = Date()
        }
    }

    private func updateLiveWaveform() {
        LiveWaveform.shared.setWanted(isStarted && Defaults[MediaSettings.useLiveWaveform] && isPlaying)
    }

    // MARK: Artwork

    private func loadArtwork(for track: TrackSnapshot, from backend: MediaBackend) {
        let key = "\(track.identity)|\(track.artworkData?.count ?? 0)|\(track.artworkURL?.absoluteString ?? "")"
        guard key != artworkKey else { return }
        artworkKey = key
        if let cached = artworkCache[track.identity] {
            artwork = cached.image
            artworkColor = cached.color
            artworkGradient = cached.gradient
            return
        }
        artworkTask?.cancel()
        let identity = track.identity
        artworkTask = Task { [weak self] in
            var image = await backend.artwork(for: track)
            if image == nil, track.bundleID == MusicBackend.bundleID,
               let url = await ITunesLookup.lookup(title: track.title, artist: track.artist)?.artworkURL {
                image = await ArtworkLoader.image(from: url)
            }
            guard let self, !Task.isCancelled, self.artworkKey == key else { return }
            if image == nil, self.artworkCache[identity] != nil { return }
            let small = image.map(Self.thumbnail(of:))
            let color = small.flatMap(ImageColors.dominantColor(of:))
            let gradient = small.flatMap(ImageColors.gradientColors(of:))
            if let image {
                if self.artworkCache.count > 40 { self.artworkCache.removeAll() }
                self.artworkCache[identity] = (image, color, gradient)
            }
            self.artwork = image
            self.artworkColor = color
            self.artworkGradient = gradient
        }
    }

    private static func thumbnail(of image: NSImage) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let small = NSImage(size: size)
        small.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        small.unlockFocus()
        return small
    }

    private func updateAppIcon(bundleID: String?) {
        guard let bundleID else {
            appIcon = nil
            return
        }
        if let cached = iconCache[bundleID] {
            appIcon = cached
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            appIcon = nil
            return
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        appIcon = icon
    }

    // MARK: Derived state

    var hasMedia: Bool { track != nil }
    var isPlaying: Bool { track?.isPlaying ?? false }

    var title: String {
        _ = settingsRevision
        guard let title = track?.title else { return "" }
        return Defaults[MediaSettings.hideMediaTitleExtras] ? TitleCleaner.clean(title) : title
    }

    var artist: String { track?.artist ?? "" }
    var album: String { track?.album ?? "" }

    var sourceAppName: String {
        let bundleID = track?.bundleID ?? preferredAppBundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "App" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Whether the closed notch should show the now-playing idle activity.
    var showsIdleActivity: Bool {
        _ = settingsRevision
        guard let track else { return false }
        if Defaults[MediaSettings.hideWhileSourceAppIsActive], isSourceAppFrontmost { return false }
        return track.isPlaying || !pauseExpired
    }

    var isSourceAppFrontmost: Bool {
        guard let bundleID = track?.bundleID else { return false }
        return bundleID == frontmostBundleID
    }

    /// The app the empty state offers to open.
    var preferredAppBundleID: String {
        switch Defaults[MediaSettings.mediaSource] {
        case .spotify: return SpotifyBackend.bundleID
        case .music: return MusicBackend.bundleID
        default:
            if let last = lastUsedBundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: last) != nil { return last }
            return Self.defaultBrowserBundleID ?? BrowserBackend.Browser.chrome.rawValue
        }
    }

    private static var defaultBrowserBundleID: String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    func supports(_ capability: MediaCapability) -> Bool { capabilities.contains(capability) }

    // MARK: Commands

    func togglePlayPause() {
        active?.send(.togglePlayPause)
    }

    func next() { active?.send(.next) }
    func previous() { active?.send(.previous) }

    func seek(to position: TimeInterval) {
        guard let track, supports(.seek) else { return }
        let target = track.duration > 0 ? min(max(position, 0), track.duration) : max(position, 0)
        active?.send(.seek(target))
    }

    func toggleShuffle() {
        guard let track else { return }
        active?.send(.setShuffle(!(track.shuffle ?? false)))
    }

    func cycleRepeat() {
        guard let track else { return }
        let current = track.repeatMode ?? .off
        let next: RepeatMode = sourceKind == .spotify ? (current == .off ? .all : .off) : current.next
        active?.send(.setRepeat(next))
    }

    func toggleLike() {
        guard let track else { return }
        active?.send(.setLiked(!(track.liked ?? false)))
    }

    func copyLink() {
        guard let track else { return }
        Task {
            var link = track.link
            if link == nil, track.bundleID == MusicBackend.bundleID || sourceKind == .system {
                link = await ITunesLookup.lookup(title: track.title, artist: track.artist)?.trackURL
            }
            let text = link?.absoluteString ?? [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " - ")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            Haptics.perform(.generic)
        }
    }

    func openSourceApp() {
        if track.map({ BrowserBackend.Browser(rawValue: $0.bundleID ?? "") != nil }) == true {
            browser.revealActiveTab()
            return
        }
        open(bundleID: track?.bundleID ?? preferredAppBundleID)
    }

    func showInApp() {
        guard let track else { return }
        switch track.bundleID {
        case MusicBackend.bundleID:
            music.revealCurrentTrack()
        case SpotifyBackend.bundleID:
            if let link = track.link, let uri = Self.spotifyURI(for: link) {
                NSWorkspace.shared.open(uri)
            } else {
                open(bundleID: SpotifyBackend.bundleID)
            }
        default:
            openSourceApp()
        }
    }


    private func open(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func spotifyURI(for link: URL) -> URL? {
        guard link.host == "open.spotify.com" else { return nil }
        let parts = link.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return URL(string: "spotify:" + parts.joined(separator: ":"))
    }
}
