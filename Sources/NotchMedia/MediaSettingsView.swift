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

    private let live = LiveWaveform.shared

    var body: some View {
        SettingsPaneView {
            Section {
                Picker("Media Source", selection: $mediaSource) {
                    ForEach(MediaSourceOption.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if mediaSource != .browser {
                    SettingsToggle(
                        "Include Browsers",
                        info: "Control music and videos playing in any browser tab.",
                        isOn: $browserSource
                    )
                }
            } header: {
                Text("Source")
            } footer: {
                Text("Automatic follows whichever player started most recently. Music and Spotify are only controlled while they are open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if browserSource || mediaSource == .browser {
                BrowserSetupSection()
            }

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
                Picker("Left Button", selection: $leftControl) {
                    ForEach(MediaExtraControl.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Right Button", selection: $rightControl) {
                    ForEach(MediaExtraControl.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }

            Section("Lock Screen") {
                Toggle("Show Volume Control", isOn: $lockVolume)
            }
        }
    }
}

private struct BrowserSetupSection: View {
    private let access = BrowserAccess.shared
    @State private var testing: BrowserBackend.Browser?

    var body: some View {
        let browsers = BrowserBackend.Browser.allCases.filter(\.isInstalled)
        Section {
            ForEach(browsers) { browser in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    statusIcon(for: browser)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(browser.name)
                        Text(detail(for: browser))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(testing == browser ? "Testing…" : "Test") {
                        testing = browser
                        Task {
                            await MediaManager.shared.browser.test(browser)
                            testing = nil
                        }
                    }
                    .disabled(testing != nil)
                }
            }
        } header: {
            Text("Browsers")
        } footer: {
            Text("Browsers only let other apps read a tab after you allow it once. Each browser also asks for permission the first time Dynamic Notch connects.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func detail(for browser: BrowserBackend.Browser) -> String {
        let status = access.statuses[browser]
        if status?.running == false { return "Open \(browser.name) to test it." }
        if status?.automationAllowed == false {
            return "Allow Dynamic Notch to control \(browser.name) in System Settings > Privacy & Security > Automation."
        }
        if status?.javaScriptAllowed == true { return "Ready. Media in any tab is detected." }
        return browser.setupHint
    }

    @ViewBuilder
    private func statusIcon(for browser: BrowserBackend.Browser) -> some View {
        let status = access.statuses[browser]
        if status?.javaScriptAllowed == true, status?.automationAllowed != false {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if status?.javaScriptAllowed == false || status?.automationAllowed == false {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }
}
