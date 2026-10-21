import AppKit
import NotchCore
import SwiftUI

struct FocusSettingsView: View {
    let controller: FocusController

    @AppStorage(FocusSettings.enabled) private var enabled
    @AppStorage(FocusSettings.duration) private var duration
    @AppStorage(FocusSettings.playSoundOnSleepFocus) private var playSoundOnSleep
    @AppStorage(FocusSettings.allowVolumeWhenFocused) private var allowVolume
    @AppStorage(FocusSettings.allowBrightnessWhenFocused) private var allowBrightness
    @AppStorage(FocusSettings.allowBatteryWhenFocused) private var allowBattery
    @AppStorage(FocusSettings.allowConnectivityWhenFocused) private var allowConnectivity

    var body: some View {
        SettingsPaneView {
            Section {
                LabeledContent("Current Focus") {
                    if let focus = SystemStatus.shared.focus {
                        Label(focus.name, systemImage: focus.symbol).foregroundStyle(focus.color)
                    } else {
                        Text(controller.hasAccess ? "None" : "Unknown").foregroundStyle(.secondary)
                    }
                }
                if !controller.hasAccess {
                    HStack {
                        Text("Reading the active Focus needs Full Disk Access.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            if let url = FocusStore.settingsURL { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }

            Section("Activity") {
                SettingsToggle("Show Focus Changes", info: "Show when a Focus turns on or off.", isOn: $enabled)
                if enabled {
                    SettingsSlider("Duration", value: $duration, in: 1...6, step: 0.5)
                    Toggle("Play Sound for Sleep Focus", isOn: $playSoundOnSleep)
                }
            }

            Section {
                Toggle("Volume", isOn: $allowVolume)
                Toggle("Brightness", isOn: $allowBrightness)
                Toggle("Battery", isOn: $allowBattery)
                Toggle("Connectivity", isOn: $allowConnectivity)
            } header: {
                Text("Allow While Focused")
            } footer: {
                Text("Activities that are turned off stay hidden while any Focus is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
