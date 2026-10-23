import AppKit
import NotchCore

/// The system Now Playing service via the private MediaRemote framework.
///
/// Since macOS 15.4 the service withholds now-playing info from unentitled processes, so on recent systems this often
/// reports nothing. That is expected: this backend then stays empty and the AppleScript sources carry the feature.
@MainActor
final class MediaRemoteBackend: MediaBackend {
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    private typealias ClientStringFn = @convention(c) (AnyObject?) -> Unmanaged<CFString>?
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void
    private typealias SetModeFn = @convention(c) (Int32) -> Void

    private enum Command: Int32 {
        case togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    private struct Functions {
        var register: RegisterFn
        var getInfo: GetInfoFn
        var getIsPlaying: GetIsPlayingFn?
        var getClient: GetClientFn?
        var clientBundleID: ClientStringFn?
        var clientParentBundleID: ClientStringFn?
        var getPID: GetPIDFn?
        var sendCommand: SendCommandFn?
        var setElapsed: SetElapsedFn?
        var setShuffle: SetModeFn?
        var setRepeat: SetModeFn?
    }

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard let register = load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self),
              let getInfo = load("MRMediaRemoteGetNowPlayingInfo", as: GetInfoFn.self) else { return nil }
        return Functions(
            register: register,
            getInfo: getInfo,
            getIsPlaying: load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self),
            getClient: load("MRMediaRemoteGetNowPlayingClient", as: GetClientFn.self),
            clientBundleID: load("MRNowPlayingClientGetBundleIdentifier", as: ClientStringFn.self),
            clientParentBundleID: load("MRNowPlayingClientGetParentAppBundleIdentifier", as: ClientStringFn.self),
            getPID: load("MRMediaRemoteGetNowPlayingApplicationPID", as: GetPIDFn.self),
            sendCommand: load("MRMediaRemoteSendCommand", as: SendCommandFn.self),
            setElapsed: load("MRMediaRemoteSetElapsedTime", as: SetElapsedFn.self),
            setShuffle: load("MRMediaRemoteSetShuffleMode", as: SetModeFn.self),
            setRepeat: load("MRMediaRemoteSetRepeatMode", as: SetModeFn.self)
        )
    }()

    private static var didRegister = false

    private var observers: [NSObjectProtocol] = []
    private var pollTask: Task<Void, Never>?
    private var fetchGeneration = 0
    private var lastBundleID: String?
    /// True once the service has delivered real info at least once; false suggests it is withholding data.
    private(set) var isDelivering = false

    init() { super.init(kind: .system) }

    override var capabilities: Set<MediaCapability> {
        var set: Set<MediaCapability> = [.skip]
        if Self.functions?.setElapsed != nil { set.insert(.seek) }
        if Self.functions?.setShuffle != nil { set.insert(.shuffle) }
        if Self.functions?.setRepeat != nil { set.insert(.repeatMode) }
        return set
    }

    override func start() {
        guard let functions = Self.functions else { return }
        super.start()
        if !Self.didRegister {
            functions.register(DispatchQueue.main)
            Self.didRegister = true
        }
        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    /// A slow poll catches seeks made inside the player; it waits for real data since a withholding service only errors.
    private func startPollingIfDelivering() {
        guard isDelivering, isRunning, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                self?.refresh()
            }
        }
    }

    override func stop() {
        pollTask?.cancel()
        pollTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        super.stop()
    }

    override func refresh() {
        guard isRunning, let functions = Self.functions else { return }
        fetchGeneration += 1
        let generation = fetchGeneration
        let startedAt = Date()
        if let getClient = functions.getClient, let bundleFn = functions.clientBundleID {
            let parentFn = functions.clientParentBundleID
            getClient(DispatchQueue.main) { [weak self] client in
                let parent = parentFn?(client)?.takeUnretainedValue() as String?
                let own = bundleFn(client)?.takeUnretainedValue() as String?
                MainActor.assumeIsolated {
                    guard let self, generation == self.fetchGeneration else { return }
                    self.lastBundleID = (parent?.isEmpty == false ? parent : nil) ?? own
                }
            }
        } else if let getPID = functions.getPID {
            getPID(DispatchQueue.main) { [weak self] pid in
                MainActor.assumeIsolated {
                    guard let self, generation == self.fetchGeneration else { return }
                    self.lastBundleID = pid > 0 ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier : nil
                }
            }
        }
        functions.getInfo(DispatchQueue.main) { [weak self] info in
            let dictionary = (info as NSDictionary?) as? [String: Any]
            MainActor.assumeIsolated {
                guard let self, generation == self.fetchGeneration, !self.isStale(readStartedAt: startedAt) else { return }
                self.handle(info: dictionary ?? [:])
            }
        }
    }

    private func handle(info: [String: Any]) {
        func value<T>(_ key: String) -> T? { info["kMRMediaRemoteNowPlayingInfo\(key)"] as? T }
        let title: String = value("Title") ?? ""
        guard !title.isEmpty else {
            publish(nil)
            return
        }
        isDelivering = true
        startPollingIfDelivering()
        var track = TrackSnapshot()
        track.title = title
        track.artist = value("Artist") ?? ""
        track.album = value("Album") ?? ""
        track.duration = (value("Duration") as NSNumber?)?.doubleValue ?? 0
        track.elapsed = (value("ElapsedTime") as NSNumber?)?.doubleValue ?? 0
        track.timestamp = value("Timestamp") ?? Date()
        let rate = (value("PlaybackRate") as NSNumber?)?.doubleValue ?? 0
        track.rate = rate > 0 ? rate : 1
        track.isPlaying = rate > 0
        track.artworkData = value("ArtworkData")
        track.isExplicit = (value("IsExplicitTrack") as NSNumber?)?.boolValue ?? false
        if let shuffle = (value("ShuffleMode") as NSNumber?)?.intValue, shuffle > 0 {
            track.shuffle = shuffle > 1
        }
        if let mode = (value("RepeatMode") as NSNumber?)?.intValue, mode > 0 {
            track.repeatMode = mode == 2 ? .one : mode == 3 ? .all : .off
        }
        if let liked = (value("IsInWishList") as NSNumber?)?.boolValue { track.liked = liked }
        track.bundleID = lastBundleID
        publish(track)

        if let getIsPlaying = Self.functions?.getIsPlaying {
            let generation = fetchGeneration
            let startedAt = Date()
            getIsPlaying(DispatchQueue.main) { [weak self] playing in
                MainActor.assumeIsolated {
                    guard let self, generation == self.fetchGeneration, !self.isStale(readStartedAt: startedAt),
                          var current = self.snapshot,
                          current.isPlaying != playing else { return }
                    current.rebase()
                    current.isPlaying = playing
                    self.publish(current)
                }
            }
        }
    }

    override func send(_ command: MediaCommand) {
        guard let functions = Self.functions else { return }
        switch command {
        case .togglePlayPause:
            _ = functions.sendCommand?(Command.togglePlayPause.rawValue, nil)
            optimistic { $0.isPlaying.toggle() }
        case .next:
            _ = functions.sendCommand?(Command.nextTrack.rawValue, nil)
        case .previous:
            _ = functions.sendCommand?(Command.previousTrack.rawValue, nil)
        case .seek(let position):
            functions.setElapsed?(position)
            optimistic { $0.elapsed = position }
        case .setShuffle(let on):
            functions.setShuffle?(on ? 3 : 1)
            optimistic { $0.shuffle = on }
        case .setRepeat(let mode):
            functions.setRepeat?(mode == .one ? 2 : mode == .all ? 3 : 1)
            optimistic { $0.repeatMode = mode }
        case .setLiked:
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.refresh()
        }
    }
}
