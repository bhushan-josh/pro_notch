import NotchCore
import SwiftUI

struct PrivacySettingsView: View {
    let controller: PrivacyController

    @AppStorage(PrivacySettings.camera) private var camera
    @AppStorage(PrivacySettings.microphone) private var microphone
    @AppStorage(PrivacySettings.showDuration) private var showDuration
    @AppStorage(PrivacySettings.compactMode) private var compactMode
    @AppStorage(PrivacySettings.playSound) private var playSound

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Camera Indicator", info: "Show a green dot while a camera is in use.", isOn: $camera)
                SettingsToggle("Microphone Indicator", info: "Show an orange dot while a microphone is in use.", isOn: $microphone)
            } header: {
                Text("Indicators")
            } footer: {
                Text("These mirror the system's own camera and microphone indicators. macOS doesn't tell other apps which app is using them, so only the indicator is shown.")
            }

            Section("Appearance") {
                SettingsToggle("Show Duration", info: "Show how long the camera or microphone has been in use.", isOn: $showDuration)
                SettingsToggle("Compact After a Few Seconds", info: "Shrink to just the colored dots after 4 seconds.", isOn: $compactMode)
                SettingsToggle("Sound and Haptic", info: "Play a sound when the camera or microphone turns on.", isOn: $playSound)
            }

            Section("Status") {
                LabeledContent("Camera") {
                    status(controller.sensors.camera, enabled: camera)
                }
                LabeledContent("Microphone") {
                    status(controller.sensors.microphone, enabled: microphone)
                }
            }
        }
    }

    private func status(_ inUse: Bool, enabled: Bool) -> some View {
        Text(!enabled ? "Not Monitored" : inUse ? "In Use" : "Not in Use")
            .foregroundStyle(enabled && inUse ? .primary : .secondary)
    }
}
