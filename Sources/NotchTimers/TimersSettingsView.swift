import NotchCore
import SwiftUI

struct TimersSettingsView: View {
    @AppStorage(TimersSettings.showInNotch) private var showInNotch
    @AppStorage(TimersSettings.showOnLockScreen) private var showOnLockScreen
    @AppStorage(TimersSettings.sound) private var sound
    @AppStorage(TimersSettings.repeatSound) private var repeatSound
    @State private var presets = TimersSettings.presetMinutes
    @State private var newPreset = 20

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Show Timer in Notch", info: "Shows the countdown beside the camera while a timer runs.", isOn: $showInNotch)
                SettingsToggle("Show on Lock Screen", info: "Adds the running timer to the lock screen widgets.", isOn: $showOnLockScreen)
            }
            Section("Alert") {
                Picker("Sound", selection: $sound) {
                    ForEach(TimerSound.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                SettingsToggle("Repeat Until Dismissed", info: "Keeps playing the sound for up to 30 seconds instead of once.", isOn: $repeatSound)
            }
            Section {
                ForEach(presets, id: \.self) { minutes in
                    LabeledContent(TimerFormat.length(TimeInterval(minutes * 60))) {
                        Button("Remove") { setPresets(presets.filter { $0 != minutes }) }
                            .disabled(presets.count <= 1)
                    }
                }
                LabeledContent("New Preset") {
                    HStack(spacing: 8) {
                        Stepper(value: $newPreset, in: 1...TimersSettings.maxPresetMinutes) {
                            Text("\(newPreset) min").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Button("Add") { setPresets(presets + [newPreset]) }
                            .disabled(presets.contains(newPreset))
                    }
                }
                Button("Restore Defaults") {
                    setPresets(TimersSettings.presets.defaultValue.compactMap { Int($0) })
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Shown as quick-start buttons on the Timers page.")
            }
        }
        .onChange(of: sound) { _, new in new.systemSound.play(volume: 0.8) }
    }

    private func setPresets(_ minutes: [Int]) {
        TimersSettings.presetMinutes = minutes
        presets = TimersSettings.presetMinutes
    }
}
