import NotchCore
import Observation
import SwiftUI

@MainActor
enum MediaActivities {
    static let idleID = "media.nowPlaying"
    /// Same id as the idle activity so the wings stay put and only the strip below animates in.
    static let peekID = idleID

    static func wings(id: String, priority: ActivityPriority, duration: TimeInterval?, peeking: Bool = false) -> LiveActivity {
        LiveActivity(
            id: id,
            category: .media,
            priority: priority,
            duration: duration,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { CompactArtworkWing(isPeeking: peeking) },
            trailing: { CompactTrailingWing() }
        )
    }

    static func presentPeek() {
        let duration = max(1, Defaults[MediaSettings.peekDuration])
        let activity = wings(id: peekID, priority: .low, duration: duration, peeking: true)
            .withBottom(height: 32) { PeekBottom() }
        ActivityCenter.shared.present(activity)
    }
}

@MainActor
@Observable
final class MediaIdleProvider: IdleActivityProvider {
    @ObservationIgnored private let manager: MediaManager

    init(manager: MediaManager) {
        self.manager = manager
    }

    var idleActivity: LiveActivity? {
        guard manager.showsIdleActivity else { return nil }
        return MediaActivities.wings(id: MediaActivities.idleID, priority: .idle, duration: nil)
    }

    var idleActivityUpdatedAt: Date { manager.lastChangeAt }
}
