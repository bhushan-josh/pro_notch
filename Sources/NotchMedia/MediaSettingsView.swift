import NotchCore
import SwiftUI

struct MediaSettingsView: View {
    @AppStorage(MediaSettings.mediaSource) private var mediaSource
    @AppStorage(MediaSettings.browserSource) private var browserSource
    @AppStorage(MediaSettings.whenMediaChanges) private var whenMediaChanges
    @AppStorage(MediaSettings.peekDuration) private var peekDuration
    @AppStorage(MediaSettings.idleDuration) private var idleDuration
    @AppStorage(MediaSettings.colorStyle) private var colorStyle
    @AppStorage(MediaSettings.leftControl) private var leftControl
    @AppStorage(MediaSettings.rightControl) private var rightControl
    @AppStorage(MediaSettings.useLiveWaveform) private var useLiveWaveform
    @AppStorage(MediaSettings.disableCompactWaveform) private var disableCompactWaveform
    @AppStorage(MediaSettings.disableArtworkFlip) private var disableArtworkFlip
    @AppStorage(MediaSettings.hideMediaTitleExtras) private var hideTitleExtras
    @AppStorage(MediaSettings.hideWhileSourceAppIsActive) private var hideWhileActive
    @AppStorage(MediaSettings.replaceWaveformDuringFocus) private var replaceDuringFocus
    @AppStorage(MediaSettings.lockScreenVolumeControl) private var lockVolume
    @AppStorage(MediaSettings.handleMediaKeys) private var handleMediaKeys
    @AppStorage(MediaSettings.showLyrics) private var showLyrics
    @AppStorage(MediaSettings.lyricsUnderNotch) private var lyricsUnderNotch
    @AppStorage(MediaSettings.lyricsOffset) private var lyricsOffset
    @AppStorage(MediaSettings.showIdleClock) private var showIdleClock

    private let live = LiveWaveform.shared

    var body: some View {
        SettingsPaneView {
            Section {
                Picker("Media Source", selection: $mediaSource) {
                    ForEach(MediaSourceOption.allCases.filter(\.isAvailable), id: \.self) { Text($0.title).tag($0) }
                }
                if mediaSource == .automatic {
                    SettingsToggle(
                        "Include Browsers",
                        info: "Control music and videos playing in any browser tab.",
                        isOn: $browserSource
                    )
                }
            } header: {
                Text("Source")
            } footer: {
                Text("Automatic follows whichever player started most recently. Choose a single player to control only that one. Players are only read while they are open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            PlayersSection(source: mediaSource, includeBrowsers: browserSource)

            Section("Activity") {
                Picker("When Media Changes", selection: $whenMediaChanges) {
                    ForEach(MediaChangeBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if whenMediaChanges == .quickPeek {
                    SettingsSlider("Peek Duration", value: $peekDuration, in: 1...8, step: 0.5)
                }
                SettingsSlider("Keep After Pausing", value: $idleDuration, in: 0...300, step: 5, format: { value in
                    value == 0 ? "Always" : String(format: "%.0fs", value)
                })
                SettingsToggle("Hide While Source App Is Active", info: "No idle activity while the player is frontmost.", isOn: $hideWhileActive)
                SettingsToggle("Show Focus During Playback", info: "Replace the waveform with the Focus symbol while a Focus is on.", isOn: $replaceDuringFocus)
            }

            Section("Appearance") {
                Picker("Color Style", selection: $colorStyle) {
                    ForEach(MediaColorStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Hide Compact Waveform", isOn: $disableCompactWaveform)
                Toggle("Disable Artwork Flip", isOn: $disableArtworkFlip)
                SettingsToggle("Hide Title Extras", info: "Strip suffixes like \"(Remastered 2011)\" or \"(feat. ...)\".", isOn: $hideTitleExtras)
                SettingsToggle("Clock When Nothing Plays", info: "Show the time, weather and your next event in place of the empty player.", isOn: $showIdleClock)
            }

            Section {
                SettingsToggle("Live Waveform", info: "Draw the waveform from the actual system audio output.", isOn: $useLiveWaveform)
            } header: {
                Text("Waveform")
            } footer: {
                if useLiveWaveform, live.isRunning, !live.hasSignal, MediaManager.shared.isPlaying {
                    Text("No audio is arriving. Check Audio Capture in Privacy & Security; the simulated waveform is used meanwhile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Controls") {
                SettingsToggle(
                    "Control with Media Keys",
                    info: "Play/pause, next and previous keys control what the notch is showing, including browser tabs.",
                    isOn: $handleMediaKeys
                )
                Picker("Left Button", selection: $leftControl) {
                    ForEach(MediaExtraControl.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Right Button", selection: $rightControl) {
                    ForEach(MediaExtraControl.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section {
                SettingsToggle("Show Lyrics", info: "Synced lyrics for the current song in the Now Playing widget.", isOn: $showLyrics)
                if showLyrics {
                    SettingsToggle("Live Lyrics Under the Notch", info: "Show the current line below the closed notch while music plays.", isOn: $lyricsUnderNotch)
                    SettingsSlider("Lyrics Timing", value: $lyricsOffset, in: -2...2, step: 0.1, format: { value in
                        abs(value) < 0.05 ? "0s" : String(format: "%+.1fs", value)
                    })
                }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics are provided by LRCLIB (lrclib.net), a free community lyrics database. The song's title, artist, album and length are sent to look them up. Raise Lyrics Timing if lines appear too early.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Lock Screen") {
                Toggle("Show Volume Control", isOn: $lockVolume)
            }
        }
    }
}

private struct PlayersSection: View {
    let source: MediaSourceOption
    let includeBrowsers: Bool

    private let access = BrowserAccess.shared
    @State private var testing: String?
    @State private var refresh = 0

    var body: some View {
        let browsers: [BrowserBackend.Browser] = {
            if let only = source.browser { return [only] }
            if source == .browser || (source == .automatic && includeBrowsers) { return BrowserBackend.Browser.allCases.filter(\.isInstalled) }
            return []
        }()
        let showsMusic = [.automatic, .music, .system].contains(source)
        Section {
            ForEach(browsers) { browser in
                row(name: browser.name, id: browser.rawValue, icon: browserIcon(browser), detail: detail(for: browser)) {
                    await MediaManager.shared.browser.test(browser)
                }
            }
            if showsMusic {
                row(name: "Music", id: MusicBackend.bundleID, icon: musicIcon, detail: musicDetail) {
                    await MediaPermissions.requestAutomation(bundleID: MusicBackend.bundleID)
                    refresh += 1
                }
            }
        } header: {
            Text("Players")
        } footer: {
            Text("Browsers only let other apps read a tab after you allow it once. Each player also asks for permission the first time Pro Notch connects.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .id(refresh)
    }

    private func row(name: String, id: String, icon: AnyView, detail: String, test: @escaping () async -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(testing == id ? "Testing…" : "Test") {
                testing = id
                Task {
                    await test()
                    testing = nil
                }
            }
            .disabled(testing != nil)
        }
    }

    private func detail(for browser: BrowserBackend.Browser) -> String {
        let status = access.statuses[browser]
        if status?.running == false { return "Open \(browser.name) to test it." }
        if status?.automationAllowed == false {
            return "Allow Pro Notch to control \(browser.name) in System Settings > Privacy & Security > Automation."
        }
        if status?.javaScriptAllowed == true { return "Ready. Media in any tab is detected." }
        return browser.setupHint
    }

    private func browserIcon(_ browser: BrowserBackend.Browser) -> AnyView {
        let status = access.statuses[browser]
        if status?.javaScriptAllowed == true, status?.automationAllowed != false { return AnyView(Self.ready) }
        if status?.javaScriptAllowed == false || status?.automationAllowed == false { return AnyView(Self.warning) }
        return AnyView(Self.unknown)
    }

    private var musicStatus: PermissionStatus { MediaPermissions.automationStatus(bundleID: MusicBackend.bundleID) }

    private var musicDetail: String {
        switch musicStatus {
        case .granted: "Ready. Controlled while Music is open."
        case .denied: "Allow Pro Notch to control Music in System Settings > Privacy & Security > Automation."
        case .notDetermined: "Test asks for permission to read and control Music."
        }
    }

    private var musicIcon: AnyView {
        switch musicStatus {
        case .granted: AnyView(Self.ready)
        case .denied: AnyView(Self.warning)
        case .notDetermined: AnyView(Self.unknown)
        }
    }

    private static var ready: some View { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
    private static var warning: some View { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
    private static var unknown: some View { Image(systemName: "circle.dashed").foregroundStyle(.secondary) }
}
