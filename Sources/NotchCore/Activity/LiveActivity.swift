import SwiftUI

public enum ActivityCategory: String, Sendable {
    case media, volume, brightness, keyboardBacklight, battery, connectivity, calendar, focus, lock, other
}

public struct ActivityPriority: Comparable, Sendable, ExpressibleByIntegerLiteral {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
    public init(integerLiteral value: Int) { self.rawValue = value }
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public static let idle: Self = 0
    public static let low: Self = 10
    public static let normal: Self = 50
    public static let high: Self = 80
    public static let critical: Self = 100
}

/// Content shown around the closed notch: a leading wing, a trailing wing and an optional strip below the camera.
///
/// Presenting an activity whose `id` is already on screen replaces it in place and restarts its timer,
/// which is how continuous updates (a volume slider, a charging percentage) avoid flicker.
public struct LiveActivity: Identifiable {
    public let id: String
    public var category: ActivityCategory
    public var priority: ActivityPriority
    /// Seconds on screen; nil keeps it until dismissed.
    public var duration: TimeInterval?
    public var leadingWidth: CGFloat
    public var trailingWidth: CGFloat
    public var bottomHeight: CGFloat
    public var leading: AnyView
    public var trailing: AnyView
    public var bottom: AnyView?
    public var onTap: (@MainActor () -> Void)?

    public init(
        id: String,
        category: ActivityCategory = .other,
        priority: ActivityPriority = .normal,
        duration: TimeInterval? = nil,
        leadingWidth: CGFloat = 32,
        trailingWidth: CGFloat = 32,
        bottomHeight: CGFloat = 0,
        @ViewBuilder leading: () -> some View,
        @ViewBuilder trailing: () -> some View,
        bottom: AnyView? = nil,
        onTap: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.category = category
        self.priority = priority
        self.duration = duration
        self.leadingWidth = leadingWidth
        self.trailingWidth = trailingWidth
        self.bottomHeight = bottom == nil ? 0 : bottomHeight
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.bottom = bottom
        self.onTap = onTap
    }

    public func withBottom<V: View>(height: CGFloat, @ViewBuilder _ content: () -> V) -> LiveActivity {
        var copy = self
        copy.bottom = AnyView(content())
        copy.bottomHeight = height
        return copy
    }
}

/// A feature that can occupy the closed notch while nothing transient is showing (e.g. now playing).
@MainActor
public protocol IdleActivityProvider: AnyObject {
    /// Read inside SwiftUI bodies; make the provider `@Observable` so changes re-render the notch.
    var idleActivity: LiveActivity? { get }
    /// Bumped whenever the idle activity meaningfully changes; used for "most recent" ordering.
    var idleActivityUpdatedAt: Date { get }
}
