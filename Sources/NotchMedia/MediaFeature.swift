import NotchCore
import SwiftUI

@MainActor
public final class MediaFeature: NotchFeature {
    private let manager = MediaManager.shared
    private var idleProvider: MediaIdleProvider?
    private var isStarted = false
    private var didRegisterStatic = false

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
            registry.register(settingsPane: SettingsPane(id: "nowPlaying", title: "Now Playing", symbol: "play.fill", color: .pink, order: 10) {
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
        manager.start()
        updateLockScreenWidget(hasMedia: manager.hasMedia)
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        manager.onTrackChange = nil
        manager.onHasMediaChange = nil
        manager.stop()
        ActivityCenter.shared.dismiss(id: MediaActivities.peekID)
        let registry = NotchRegistry.shared
        registry.unregister(homeWidgetID: "media")
        registry.unregister(lockScreenWidgetID: "media")
        SystemStatus.shared.isMediaPlaying = false
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
