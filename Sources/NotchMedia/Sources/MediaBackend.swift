import AppKit
import NotchCore

enum MediaSourceKind: String, Sendable {
    case music, spotify, system, browser
}

enum RepeatMode: String, Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

enum MediaCommand: Sendable {
    case togglePlayPause, play, pause, next, previous
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
    case setLiked(Bool)
}

enum MediaCapability: Sendable {
    case seek, shuffle, repeatMode, like, skip
}

struct TrackSnapshot: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0
    /// Position at `timestamp`; extrapolate with `elapsed(at:)`.
    var elapsed: TimeInterval = 0
    var timestamp = Date()
    var rate: Double = 1
    var isPlaying = false
    var bundleID: String?
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var liked: Bool?
    var isExplicit = false
    var link: URL?
    var artworkURL: URL?
    var artworkData: Data?

    var identity: String { "\(bundleID ?? "")|\(title)|\(artist)" }
    var isEmpty: Bool { title.isEmpty && artist.isEmpty }

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else { return clamp(elapsed) }
        return clamp(elapsed + date.timeIntervalSince(timestamp) * max(rate, 0))
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    /// Rebases the stored position to now, e.g. before flipping play state optimistically.
    mutating func rebase(to date: Date = Date()) {
        elapsed = elapsed(at: date)
        timestamp = date
    }
}

/// One place now-playing data can come from. Subclasses publish snapshots; MediaManager picks between them.
@MainActor
class MediaBackend {
    let kind: MediaSourceKind
    private(set) var snapshot: TrackSnapshot?
    /// Last time this source was playing or changed track; used to choose between sources automatically.
    private(set) var lastActiveAt = Date.distantPast
    /// When the user last sent a command; reads that began before it would overwrite the optimistic update.
    private(set) var lastCommandAt = Date.distantPast
    var onChange: (@MainActor () -> Void)?
    var capabilities: Set<MediaCapability> { [.skip, .seek] }
    var isRunning = false

    init(kind: MediaSourceKind) {
        self.kind = kind
    }

    func start() { isRunning = true }
    func stop() {
        isRunning = false
        publish(nil)
    }
    func refresh() {}
    func send(_ command: MediaCommand) {}

    func artwork(for track: TrackSnapshot) async -> NSImage? {
        if let data = track.artworkData, let image = NSImage(data: data) { return image }
        if let url = track.artworkURL { return await ArtworkLoader.image(from: url) }
        return nil
    }

    /// True when a read that began at `start` predates the last command, or ran too soon after it to reflect it.
    func isStale(readStartedAt start: Date) -> Bool {
        start < lastCommandAt.addingTimeInterval(0.25)
    }

    func publish(_ new: TrackSnapshot?) {
        // A read still in flight during stop() must not leave a stale track behind.
        if new != nil, !isRunning { return }
        guard var new, !new.isEmpty else {
            guard snapshot != nil else { return }
            snapshot = nil
            onChange?()
            return
        }
        if let old = snapshot, old.identity == new.identity, old.isPlaying == new.isPlaying,
           abs(old.elapsed(at: new.timestamp) - new.elapsed) < 1.5 {
            // Polled positions drift by a fraction of a second; keeping the old anchor stops the UI from jittering.
            new.elapsed = old.elapsed
            new.timestamp = old.timestamp
        }
        if (new.isPlaying && snapshot?.isPlaying != true) || new.identity != snapshot?.identity { lastActiveAt = Date() }
        guard new != snapshot else { return }
        snapshot = new
        onChange?()
    }

    /// Applies a local guess right after a command so the UI responds before the next poll.
    func optimistic(_ update: (inout TrackSnapshot) -> Void) {
        guard var current = snapshot else { return }
        current.rebase()
        update(&current)
        snapshot = current
        lastActiveAt = Date()
        lastCommandAt = Date()
        onChange?()
    }
}

/// Backends that read an app via AppleScript on a light poll, refreshed early by distributed notifications.
@MainActor
class PollingBackend: MediaBackend {
    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isPolling = false
    private var pendingRefresh = false
    private var pollStartedAt: Date?

    var playingInterval: TimeInterval { 1 }
    var idleInterval: TimeInterval { 3 }
    var notificationNames: [String] { [] }
    var watchedBundleIDs: [String] { [] }

    func poll() async {}

    override func publish(_ new: TrackSnapshot?) {
        if isRunning, let pollStartedAt, isStale(readStartedAt: pollStartedAt) { return }
        super.publish(new)
    }

    /// Runs a state script. "Can't get" errors mean there is no current track, so they clear the snapshot;
    /// other failures (timeouts, a busy app) keep the last known state rather than flickering.
    func runStateScript(_ source: String) async -> NSAppleEventDescriptor? {
        do {
            return try await AppleScriptRunner.run(source)
        } catch let error as AppleScriptRunner.ScriptError where error.code == -1728 || error.code == -1719 {
            publish(nil)
            return nil
        } catch {
            return nil
        }
    }

    override func start() {
        super.start()
        let distributed = DistributedNotificationCenter.default()
        for name in notificationNames {
            observers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                MainActor.assumeIsolated {
                    guard let self, let bundleID, self.watchedBundleIDs.contains(bundleID) else { return }
                    self.refresh()
                }
            })
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runPoll()
                let interval = self.snapshot?.isPlaying == true ? self.playingInterval : self.idleInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    override func stop() {
        pollTask?.cancel()
        pollTask = nil
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in observers {
            distributed.removeObserver(observer)
            workspace.removeObserver(observer)
        }
        observers.removeAll()
        super.stop()
    }

    override func refresh() {
        guard isRunning else { return }
        Task { await runPoll() }
    }

    /// Re-polls shortly after a command so the app has time to apply it.
    func refreshSoon(_ delay: TimeInterval = 0.35) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.refresh()
        }
    }

    private func runPoll() async {
        guard isRunning else { return }
        if isPolling {
            pendingRefresh = true
            return
        }
        isPolling = true
        repeat {
            pendingRefresh = false
            pollStartedAt = Date()
            await poll()
        } while pendingRefresh && isRunning
        pollStartedAt = nil
        isPolling = false
    }
}

enum ArtworkLoader {
    static func image(from url: URL) async -> NSImage? {
        if url.isFileURL { return NSImage(contentsOf: url) }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return NSImage(data: data)
    }
}

enum ScriptText {
    /// Escapes a string for embedding inside an AppleScript string literal.
    static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

extension NSAppleEventDescriptor {
    func item(_ index: Int) -> NSAppleEventDescriptor? {
        guard index <= numberOfItems else { return nil }
        let item = atIndex(index)
        guard let item, item.descriptorType != typeType || item.typeCodeValue != OSType(0x6D736E67) else { return nil }
        return item
    }

    func string(_ index: Int) -> String { item(index)?.stringValue ?? "" }
    func double(_ index: Int) -> Double {
        guard let item = item(index) else { return 0 }
        if let string = item.stringValue, let value = Double(string.replacingOccurrences(of: ",", with: ".")) { return value }
        return item.doubleValue
    }
    func bool(_ index: Int) -> Bool? {
        guard let item = item(index) else { return nil }
        if item.descriptorType == typeTrue { return true }
        if item.descriptorType == typeFalse { return false }
        if let string = item.stringValue { return string == "true" }
        return item.booleanValue
    }
}
