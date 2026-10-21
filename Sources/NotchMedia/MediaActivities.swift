import NotchCore
import Observation
import SwiftUI

@MainActor
enum MediaActivities {
    static let idleID = "media.nowPlaying"
    static let peekID = "media.peek"

    static func wings(id: String, priority: ActivityPriority, duration: TimeInterval?) -> LiveActivity {
        LiveActivity(
            id: id,
            category: .media,
            priority: priority,
            duration: duration,
            leadingWidth: 24,
            trailingWidth: 24,
            leading: { CompactArtworkWing() },
            trailing: { CompactTrailingWing() }
        )
    }

    static func presentPeek() {
        let duration = max(1, Defaults[MediaSettings.peekDuration])
        let activity = wings(id: peekID, priority: .low, duration: duration)
            .withBottom(height: 34) { PeekBottom() }
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
