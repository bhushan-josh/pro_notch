import AppKit
import CoreGraphics
import NotchCore

/// Tracks the session lock and screen saver through the distributed notifications loginwindow posts.
@MainActor
final class LockMonitor {
    enum Event {
        case locked, unlocked, screenSaverStarted, screenSaverStopped
    }

    var onEvent: ((Event) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = DistributedNotificationCenter.default()
        let mapping: [(String, Event)] = [
            ("com.apple.screenIsLocked", .locked),
            ("com.apple.screenIsUnlocked", .unlocked),
            ("com.apple.screensaver.didstart", .screenSaverStarted),
            ("com.apple.screensaver.didstop", .screenSaverStopped),
        ]
        for (name, event) in mapping {
            observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(event) }
            })
        }
        if Self.sessionIsLocked { handle(.locked) }
    }

    func stop() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    private func handle(_ event: Event) {
        let status = SystemStatus.shared
        switch event {
        case .locked:
            guard !status.isScreenLocked else { return }
            status.isScreenLocked = true
        case .unlocked:
            guard status.isScreenLocked else { return }
            status.isScreenLocked = false
        case .screenSaverStarted:
            guard !status.isScreenSaverActive else { return }
            status.isScreenSaverActive = true
        case .screenSaverStopped:
            guard status.isScreenSaverActive else { return }
            status.isScreenSaverActive = false
        }
        onEvent?(event)
    }

    private static var sessionIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
