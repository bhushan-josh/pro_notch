import NotchCore
import SwiftUI

@MainActor
public final class MediaFeature: NotchFeature {
    private let manager = MediaManager.shared
    private var idleProvider: MediaIdleProvider?
    private var isStarted = false
    private var didRegisterStatic = false
    /// Cached so the media key handler never touches UserDefaults inside the event tap.
    private var handlesMediaKeys = true
    private var mediaKeysWatcher: SettingsWatcher?

    public init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let registry = NotchRegistry.shared
        let manager = manager

        if !didRegisterStatic {
            didRegisterStatic = true
            let provider = MediaIdleProvider(manager: manager)
            idleProvider = provider
            registry.register(idleProvider: provider)
            registry.register(swipeHandler: { [weak self] direction in
                guard let self, self.isStarted, manager.hasMedia else { return false }
                switch direction {
                case .right: manager.next()
                case .left: manager.previous()
                case .up, .down: return false
                }
                return true
            })
            registry.register(settingsPane: SettingsPane(id: "nowPlaying", title: "Now Playing", symbol: "play.fill", color: .pink, category: .liveActivities, order: 10) {
                MediaSettingsView()
            })
            MediaPermissions.register()
        }

        registry.register(homeWidget: HomeWidget(id: "media", kind: .nowPlaying) {
            NowPlayingWidget()
        })

        manager.onTrackChange = { [weak self] track in
            guard let self, self.isStarted, track.isPlaying,
                  Defaults[MediaSettings.whenMediaChanges] == .quickPeek,
                  !(Defaults[MediaSettings.hideWhileSourceAppIsActive] && manager.isSourceAppFrontmost) else { return }
            MediaActivities.presentPeek()
        }
        manager.onHasMediaChange = { [weak self] hasMedia in
            self?.updateLockScreenWidget(hasMedia: hasMedia)
            if !hasMedia { ActivityCenter.shared.dismiss(id: MediaActivities.peekID) }
        }

        handlesMediaKeys = Defaults[MediaSettings.handleMediaKeys]
        mediaKeysWatcher = SettingsWatcher([MediaSettings.handleMediaKeys.name]) { [weak self] in
            self?.handlesMediaKeys = Defaults[MediaSettings.handleMediaKeys]
        }
        registry.mediaKeyHandler = { [weak self] key in
            self?.claim(key) ?? false
        }

        LyricsManager.shared.start()
        manager.start()
        updateLockScreenWidget(hasMedia: manager.hasMedia)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        manager.onTrackChange = nil
        manager.onHasMediaChange = nil
        let registry = NotchRegistry.shared
        registry.mediaKeyHandler = nil
        mediaKeysWatcher = nil
        LyricsManager.shared.stop()
        manager.stop()
        ActivityCenter.shared.dismiss(id: MediaActivities.peekID)
        registry.unregister(homeWidgetID: "media")
        registry.unregister(lockScreenWidgetID: "media")
        SystemStatus.shared.isMediaPlaying = false
    }

    /// Runs inside the HUD's key event tap: decides from cached state and defers the command.
    private func claim(_ key: MediaTransportKey) -> Bool {
        // Every backend accepts transport commands, so any current track can take the key.
        guard isStarted, handlesMediaKeys, manager.track != nil, manager.sourceKind != nil else { return false }
        let manager = manager
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Self.perform(key, on: manager) }
        }
        return true
    }

    private static func perform(_ key: MediaTransportKey, on manager: MediaManager) {
        switch key {
        case .playPause:
            manager.togglePlayPause()
        case .next:
            manager.next()
        case .previous:
            manager.previous()
        case .fastForward, .rewind:
            let forward = key == .fastForward
            guard let track = manager.track, manager.supports(.seek) else {
                if forward { manager.next() } else { manager.previous() }
                return
            }
            manager.seek(to: track.elapsed(at: Date()) + (forward ? 10 : -10))
        }
    }

    private func updateLockScreenWidget(hasMedia: Bool) {
        let registry = NotchRegistry.shared
        if hasMedia, isStarted {
            registry.register(lockScreenWidget: LockScreenWidget(id: "media", order: 0) {
                LockScreenMediaView()
            })
        } else {
            registry.unregister(lockScreenWidgetID: "media")
        }
    }
}
