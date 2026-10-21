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
                SettingsToggle(
                    "Include Browsers",
                    info: "Safari, Chrome and Dia. Turn on \"Allow JavaScript from Apple Events\" in the browser's Develop menu.",
                    isOn: $browserSource
                )
            } header: {
                Text("Source")
            } footer: {
                Text("Automatic follows whichever player started most recently. The system source may report nothing for some apps on recent macOS versions; Music and Spotify are read directly.")
                    .font(.caption).foregroundStyle(.secondary)
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
