import NotchCore
import SwiftUI

public enum MediaSourceOption: String, CaseIterable, Sendable {
    case automatic, music, spotify, system

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .music: "Music"
        case .spotify: "Spotify"
        case .system: "System (Now Playing)"
        }
    }
}

public enum MediaChangeBehavior: String, CaseIterable, Sendable {
    case none, quickPeek

    var title: String {
        switch self {
        case .none: "Do Nothing"
        case .quickPeek: "Quick Peek"
        }
    }
}

public enum MediaColorStyle: String, CaseIterable, Sendable {
    case artwork, color, gradient, mono

    var title: String {
        switch self {
        case .artwork: "Artwork"
        case .color: "Accent Color"
        case .gradient: "Gradient"
        case .mono: "Mono"
        }
    }
}

public enum MediaExtraControl: String, CaseIterable, Sendable {
    case none, shuffle
    case repeatMode = "repeat"
    case like, favorite, copy

    var title: String {
        switch self {
        case .none: "None"
        case .shuffle: "Shuffle"
        case .repeatMode: "Repeat"
        case .like: "Like"
        case .favorite: "Favorite"
        case .copy: "Copy Link"
        }
    }
}

public enum MediaSettings {
    public static let mediaSource = SettingKey("nowPlaying.mediaSource", default: MediaSourceOption.automatic)
    public static let browserSource = SettingKey("nowPlaying.browserSource", default: false)
    public static let whenMediaChanges = SettingKey("nowPlaying.whenMediaChanges", default: MediaChangeBehavior.quickPeek)
    public static let peekDuration = SettingKey("nowPlaying.peekDuration", default: 3.0)
    /// Seconds the idle activity survives a pause; 0 keeps it until the player stops.
    public static let idleDuration = SettingKey("nowPlaying.idleDuration", default: 30.0)
    public static let colorStyle = SettingKey("nowPlaying.colorStyle", default: MediaColorStyle.artwork)
    public static let leftControl = SettingKey("nowPlaying.leftControl", default: MediaExtraControl.shuffle)
    public static let rightControl = SettingKey("nowPlaying.rightControl", default: MediaExtraControl.repeatMode)
    public static let useLiveWaveform = SettingKey("nowPlaying.useLiveWaveform", default: false)
    public static let disableCompactWaveform = SettingKey("nowPlaying.disableCompactWaveform", default: false)
    public static let disableArtworkFlip = SettingKey("nowPlaying.disableArtworkFlip", default: false)
    public static let hideMediaTitleExtras = SettingKey("nowPlaying.hideMediaTitleExtras", default: false)
    public static let hideWhileSourceAppIsActive = SettingKey("nowPlaying.hideWhileSourceAppIsActive", default: false)
    public static let replaceWaveformDuringFocus = SettingKey("nowPlaying.replaceWaveformDuringFocus", default: true)
    public static let lockScreenVolumeControl = SettingKey("lockScreen.nowPlaying.showVolumeControl", default: false)

    static let audioCaptureConfirmed = SettingKey("nowPlaying.internal.audioCaptureConfirmed", default: false)

    static var allNames: [String] {
        [
            mediaSource.name, browserSource.name, whenMediaChanges.name, peekDuration.name, idleDuration.name,
            colorStyle.name, leftControl.name, rightControl.name, useLiveWaveform.name,
            disableCompactWaveform.name, disableArtworkFlip.name, hideMediaTitleExtras.name,
            hideWhileSourceAppIsActive.name, replaceWaveformDuringFocus.name, lockScreenVolumeControl.name,
        ]
    }
}

/// Fires when any of the given defaults change. `Defaults.observe` relies on KVO, which does not see dotted key
/// names like `nowPlaying.mediaSource`, so this compares values on every UserDefaults change notification instead.
@MainActor
final class SettingsWatcher {
    private var observer: NSObjectProtocol?
    private var signature: [String]

    init(_ names: [String], _ handler: @escaping @MainActor () -> Void) {
        let read = { names.map { String(describing: Defaults.store.object(forKey: $0) ?? "-") } }
        signature = read()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = read()
                guard current != self.signature else { return }
                self.signature = current
                handler()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}
