import Foundation

public enum DisplayTarget: String, CaseIterable, Sendable {
    case builtIn, main, all, specific

    public var title: String {
        switch self {
        case .builtIn: "Built-in Display"
        case .main: "Main Screen"
        case .all: "All Displays"
        case .specific: "Specific Display"
        }
    }
}

/// What the expanded notch shows on its Home page.
public enum ExpandedHome: String, CaseIterable, Sendable {
    case duo, nowPlaying, calendar, none

    public var title: String {
        switch self {
        case .duo: "Duo"
        case .nowPlaying: "Now Playing"
        case .calendar: "Calendar"
        case .none: "None"
        }
    }
}

public enum ProgressStyle: String, CaseIterable, Sendable {
    case white, accent, stylized, glow

    public var title: String {
        switch self {
        case .white: "White"
        case .accent: "Accent"
        case .stylized: "Stylized"
        case .glow: "Glow"
        }
    }
}

public enum CoreSettings {
    public static let launchAtLogin = SettingKey("general.launchAtLogin", default: false)
    public static let displayTarget = SettingKey("general.displayTarget", default: DisplayTarget.builtIn)
    public static let specificDisplayUUID = SettingKey("general.specificDisplayUUID", default: "")
    public static let forceSimulatedNotch = SettingKey("general.forceSimulatedNotch", default: false)

    public static let expandOnHover = SettingKey("general.expandOnHover", default: true)
    public static let hoverDuration = SettingKey("general.hoverDuration", default: 0.25)
    public static let haptics = SettingKey("general.haptics", default: true)
    public static let contrastOutline = SettingKey("general.contrastOutline", default: false)
    public static let progressiveBlur = SettingKey("general.progressiveBlur", default: true)

    public static let swipeToToggle = SettingKey("general.gestures.swipeToToggle", default: true)
    public static let swipeToDismiss = SettingKey("general.gestures.swipeToDismiss", default: true)
    public static let swipeToSkip = SettingKey("general.gestures.swipeToSkip", default: true)
    public static let swipeToCycleActivity = SettingKey("general.gestures.swipeToCycleActivity", default: false)
    public static let naturalMovement = SettingKey("general.gestures.naturalMovement", default: true)
    public static let useAccentColor = SettingKey("general.gestures.useAccentColor", default: false)

    public static let hideFromScreenCapture = SettingKey("general.hideFromScreenCapture", default: false)
    public static let hideInFullscreen = SettingKey("general.hideInFullscreen", default: true)
    public static let hideInMissionControl = SettingKey("general.hideInMissionControl", default: true)
    public static let hideMenuBarIcon = SettingKey("general.hideMenuBarIcon", default: false)
    public static let showOnLockScreen = SettingKey("general.showOnLockScreen", default: true)

    public static let expandedHome = SettingKey("general.idleActivity.expanded", default: ExpandedHome.duo)
    /// When several idle activities are available, prefer the one that changed last.
    public static let idleMostRecent = SettingKey("general.idleActivity.mostRecent", default: true)

    /// Extra points added to the detected notch size; negative values shrink it.
    public static let notchWidthOffset = SettingKey("general.tuning.notchWidth", default: 0.0)
    public static let notchHeightOffset = SettingKey("general.tuning.notchHeight", default: 0.0)

    public static let activityDuration = SettingKey("general.activityDuration", default: 2.0)
    public static let hudProgressStyle = SettingKey("hud.progressStyle", default: ProgressStyle.white)

    public static let onboardingCompleted = SettingKey("app.onboardingCompleted", default: false)
}
