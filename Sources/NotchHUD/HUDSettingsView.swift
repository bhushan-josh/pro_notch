import ApplicationServices
import SwiftUI
import NotchCore

struct HUDSettingsView: View {
    let outputs: OutputDevices
    let volume: VolumeManager

    @AppStorage(HUDSettings.enableVolume) private var enableVolume
    @AppStorage(HUDSettings.enableBrightness) private var enableBrightness
    @AppStorage(HUDSettings.enableKeyboard) private var enableKeyboard
    @AppStorage(HUDSettings.replaceSystemHUD) private var replaceSystemHUD
    @AppStorage(HUDSettings.showPercentage) private var showPercentage
    @AppStorage(HUDSettings.duration) private var duration
    @AppStorage(HUDSettings.speed) private var speed
    @AppStorage(HUDSettings.betterDisplayIntegration) private var betterDisplay
    @AppStorage(HUDSettings.notifyOnOutputChange) private var notifyOnOutputChange
    @AppStorage(CoreSettings.hudProgressStyle) private var progressStyle

    var body: some View {
        SettingsPaneView {
            Section {
                Toggle("Volume", isOn: $enableVolume)
                Toggle("Display Brightness", isOn: $enableBrightness)
                Toggle("Keyboard Backlight", isOn: $enableKeyboard)
            } header: {
                Text("Show HUD For")
            }

            Section("System HUD") {
                SettingsToggle(
                    "Replace System HUD",
                    info: "Handle the volume, brightness and keyboard keys here so the system overlay stays hidden. Hold Shift and Option for finer steps.",
                    isOn: $replaceSystemHUD
                )
                if replaceSystemHUD {
                    AccessibilityStatusRow()
                }
                SettingsToggle(
                    "BetterDisplay Integration",
                    info: "Show the HUD for external display changes that BetterDisplay broadcasts.",
                    isOn: $betterDisplay
                )
            }

            Section("Appearance") {
                Picker("Progress Style", selection: $progressStyle) {
                    ForEach(ProgressStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Animation", selection: $speed) {
                    ForEach(HUDSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Show Percentage", isOn: $showPercentage)
                SettingsSlider("Duration", value: $duration, in: 0.5...5, step: 0.25, format: { String(format: "%.2fs", $0) })
                HUDPreview(style: progressStyle, showPercentage: showPercentage)
            }

            Section("Sound") {
                Picker("Output Device", selection: outputSelection) {
                    if outputs.defaultDevice == nil {
                        Text("None").tag("")
                    }
                    ForEach(outputs.devices) { device in
                        Label(device.name, systemImage: device.symbol).tag(device.uid)
                    }
                }
                LabeledContent("Output Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: volumeBinding, in: 0...1).frame(minWidth: 140)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .disabled(!volume.canSetVolume)
                }
                if !volume.canSetVolume {
                    Text("This output does not support software volume control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SettingsToggle("Notify on Output Change", info: "Show the new device in the notch when the output switches.", isOn: $notifyOnOutputChange)
            }
        }
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { outputs.defaultDevice?.uid ?? "" },
            set: { outputs.setDefault(uid: $0) }
        )
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { volume.effectiveVolume },
            set: { volume.setVolume($0) }
        )
    }
}

private struct AccessibilityStatusRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            if AXIsProcessTrusted() {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Label("Needs Accessibility access to intercept keys", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Grant Access") { MediaKeyManager.requestTrust() }
                }
            }
        }
    }
}

private struct HUDPreview: View {
    let style: ProgressStyle
    let showPercentage: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 40)
            NotchProgressBar(value: 0.62, style: style)
                .frame(width: showPercentage ? 52 : 80)
            if showPercentage {
                Text("62%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(width: 280, height: 32)
        .background(.black, in: Capsule())
        .frame(maxWidth: .infinity)
    }
}
