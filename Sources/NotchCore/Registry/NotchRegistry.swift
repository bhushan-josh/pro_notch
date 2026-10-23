import SwiftUI
import Observation

/// A self-contained module (media, HUD, calendar...). The app creates each feature once and calls `start()` at launch.
@MainActor
public protocol NotchFeature: AnyObject {
    /// Register pages, widgets, settings panes and permissions with `NotchRegistry.shared`, then begin monitoring.
    func start()
    func stop()
}

/// A tab of the expanded notch (Home, Downloads...).
public struct NotchPage: Identifiable {
    public let id: String
    public var title: String
    public var symbol: String
    public var order: Int
    /// Set to let the user drag the open island's bottom edge and corners to resize this page.
    public var resize: PageResize?
    public var content: () -> AnyView

    public init(id: String, title: String, symbol: String, order: Int, resize: PageResize? = nil, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.order = order
        self.resize = resize
        self.content = { AnyView(content()) }
    }
}

public enum HomeWidgetKind: String, Sendable {
    case nowPlaying, calendar
}

/// A card on the expanded Home page. `ExpandedHome` picks which kinds are shown.
public struct HomeWidget: Identifiable {
    public let id: String
    public var kind: HomeWidgetKind
    public var content: () -> AnyView

    public init(id: String, kind: HomeWidgetKind, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.kind = kind
        self.content = { AnyView(content()) }
    }
}

/// Sidebar group a settings pane is listed under, in display order.
public enum SettingsCategory: Int, CaseIterable, Identifiable, Sendable {
    case general, notifications, liveActivities, app

    public var id: Int { rawValue }

    /// Header shown above the group; `nil` lists the panes without one.
    public var title: String? {
        switch self {
        case .general: nil
        case .notifications: "Notifications"
        case .liveActivities: "Live Activities"
        case .app: "Dynamic Notch"
        }
    }
}

public struct SettingsPane: Identifiable {
    public let id: String
    public var title: String
    public var symbol: String
    /// SF Symbol tile color in the settings sidebar.
    public var color: Color
    public var category: SettingsCategory
    /// Position within its category.
    public var order: Int
    public var content: () -> AnyView

    public init(id: String, title: String, symbol: String, color: Color, category: SettingsCategory, order: Int, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.color = color
        self.category = category
        self.order = order
        self.content = { AnyView(content()) }
    }
}

/// A view shown on the lock screen widget stack (now playing, weather...).
public struct LockScreenWidget: Identifiable {
    public let id: String
    public var order: Int
    public var content: () -> AnyView

    public init(id: String, order: Int, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.order = order
        self.content = { AnyView(content()) }
    }
}

public enum PermissionStatus: Sendable {
    case granted, denied, notDetermined
}

public struct PermissionRequirement: Identifiable {
    public let id: String
    public var title: String
    public var description: String
    public var symbol: String
    public var status: @MainActor () -> PermissionStatus
    public var request: @MainActor () async -> Void
    public var settingsURL: URL?

    public init(
        id: String, title: String, description: String, symbol: String,
        settingsURL: URL? = nil,
        status: @escaping @MainActor () -> PermissionStatus,
        request: @escaping @MainActor () async -> Void
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.symbol = symbol
        self.settingsURL = settingsURL
        self.status = status
        self.request = request
    }
}

/// Hardware media keys (F7-F9 and friends) the notch's player can claim.
public enum MediaTransportKey: Sendable {
    case playPause, next, previous, fastForward, rewind
}

/// A small control in the expanded island's header, beside the settings button.
public struct HeaderAccessory: Identifiable {
    public let id: String
    public var order: Int
    public var content: () -> AnyView

    public init(id: String, order: Int, @ViewBuilder content: @escaping () -> some View) {
        self.id = id
        self.order = order
        self.content = { AnyView(content()) }
    }
}

public enum SwipeDirection: Sendable {
    case left, right, up, down
}

@MainActor
@Observable
public final class NotchRegistry {
    public static let shared = NotchRegistry()

    public private(set) var pages: [NotchPage] = []
    public private(set) var homeWidgets: [HomeWidget] = []
    public private(set) var settingsPanes: [SettingsPane] = []
    public private(set) var lockScreenWidgets: [LockScreenWidget] = []
    public private(set) var permissions: [PermissionRequirement] = []
    @ObservationIgnored public private(set) var idleProviders: [IdleActivityProvider] = []

    /// Horizontal swipes on the notch; the first handler returning true consumes it.
    @ObservationIgnored public private(set) var swipeHandlers: [(SwipeDirection) -> Bool] = []

    @ObservationIgnored public var openSettings: (@MainActor (_ paneID: String?) -> Void)?

    /// Claims a hardware media key; return true to consume it. Runs inside the key event tap, so it must
    /// decide from cached state and do any real work asynchronously.
    @ObservationIgnored public var mediaKeyHandler: (@MainActor (MediaTransportKey) -> Bool)?

    public private(set) var headerAccessories: [HeaderAccessory] = []

    public func register(headerAccessory: HeaderAccessory) {
        headerAccessories.removeAll { $0.id == headerAccessory.id }
        headerAccessories.append(headerAccessory)
        headerAccessories.sort { $0.order < $1.order }
    }

    public func unregister(headerAccessoryID: String) { headerAccessories.removeAll { $0.id == headerAccessoryID } }

    private init() {}

    public func register(page: NotchPage) {
        pages.removeAll { $0.id == page.id }
        pages.append(page)
        pages.sort { $0.order < $1.order }
    }

    public func register(homeWidget: HomeWidget) {
        homeWidgets.removeAll { $0.id == homeWidget.id }
        homeWidgets.append(homeWidget)
    }

    public func register(settingsPane: SettingsPane) {
        settingsPanes.removeAll { $0.id == settingsPane.id }
        settingsPanes.append(settingsPane)
        settingsPanes.sort { $0.order < $1.order }
    }

    public func register(lockScreenWidget: LockScreenWidget) {
        lockScreenWidgets.removeAll { $0.id == lockScreenWidget.id }
        lockScreenWidgets.append(lockScreenWidget)
        lockScreenWidgets.sort { $0.order < $1.order }
    }

    public func register(permission: PermissionRequirement) {
        permissions.removeAll { $0.id == permission.id }
        permissions.append(permission)
    }

    public func register(idleProvider: IdleActivityProvider) {
        guard !idleProviders.contains(where: { $0 === idleProvider }) else { return }
        idleProviders.append(idleProvider)
    }

    public func register(swipeHandler: @escaping (SwipeDirection) -> Bool) {
        swipeHandlers.append(swipeHandler)
    }

    public func unregister(pageID: String) { pages.removeAll { $0.id == pageID } }
    public func unregister(homeWidgetID: String) { homeWidgets.removeAll { $0.id == homeWidgetID } }
    public func unregister(lockScreenWidgetID: String) { lockScreenWidgets.removeAll { $0.id == lockScreenWidgetID } }

    func handleSwipe(_ direction: SwipeDirection) -> Bool {
        swipeHandlers.contains { $0(direction) }
    }
}
