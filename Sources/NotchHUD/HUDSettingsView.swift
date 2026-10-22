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

            LevelColorsSection()

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

private struct LevelColorsSection: View {
    @AppStorage(HUDSettings.levelColorMode) private var mode
    @AppStorage(HUDSettings.levelColorsVolume) private var volume
    @AppStorage(HUDSettings.levelColorsBrightness) private var brightness
    @AppStorage(HUDSettings.levelColorsKeyboard) private var keyboard
    @AppStorage(HUDSettings.levelColorsTintIcon) private var tintIcon
    @AppStorage(HUDSettings.levelMidThreshold) private var midThreshold
    @AppStorage(HUDSettings.levelHighThreshold) private var highThreshold
    @AppStorage(HUDSettings.levelLowColor) private var lowHex
    @AppStorage(HUDSettings.levelMidColor) private var midHex
    @AppStorage(HUDSettings.levelHighColor) private var highHex
    @AppStorage(CoreSettings.hudProgressStyle) private var progressStyle
    @State private var previewLevel = 0.65

    var body: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(LevelColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if mode != .off {
                Toggle("Volume", isOn: $volume)
                Toggle("Brightness", isOn: $brightness)
                Toggle("Keyboard Backlight", isOn: $keyboard)
                Toggle("Tint Icon to Match", isOn: $tintIcon)
                SettingsSlider("Mid Color From", value: midBinding, in: 0.05...0.9, step: 0.05, format: percent)
                SettingsSlider("High Color From", value: highBinding, in: 0.1...1, step: 0.05, format: percent)
                ColorPicker("Low", selection: color($lowHex, fallback: .green), supportsOpacity: false)
                ColorPicker("Mid", selection: color($midHex, fallback: .yellow), supportsOpacity: false)
                ColorPicker("High", selection: color($highHex, fallback: .red), supportsOpacity: false)
                LevelPreview(level: $previewLevel, style: progressStyle, colors: HUDSettings.levelColors, tintIcon: tintIcon)
                Button("Reset Colors") {
                    lowHex = HUDSettings.levelLowColor.defaultValue
                    midHex = HUDSettings.levelMidColor.defaultValue
                    highHex = HUDSettings.levelHighColor.defaultValue
                    midThreshold = HUDSettings.levelMidThreshold.defaultValue
                    highThreshold = HUDSettings.levelHighThreshold.defaultValue
                }
            }
        } header: {
            Text("Level Colors")
        } footer: {
            Text(mode.info).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var percent: (Double) -> String { { "\(Int(($0 * 100).rounded()))%" } }

    private var midBinding: Binding<Double> {
        Binding(get: { midThreshold }, set: { value in
            midThreshold = value
            if highThreshold <= value { highThreshold = min(1, value + 0.05) }
        })
    }

    private var highBinding: Binding<Double> {
        Binding(get: { highThreshold }, set: { value in
            highThreshold = value
            if midThreshold >= value { midThreshold = max(0.05, value - 0.05) }
        })
    }

    private func color(_ hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) ?? fallback }, set: { hex.wrappedValue = $0.hexString })
    }
}

/// A draggable sample bar so the thresholds can be tried without pressing keys.
private struct LevelPreview: View {
    @Binding var level: Double
    let style: ProgressStyle
    let colors: LevelColors
    let tintIcon: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: level < 0.01 ? "speaker.slash.fill" : level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tintIcon ? colors.color(at: level) : .white)
                Spacer(minLength: 40)
                NotchProgressBar(value: level, style: style, levelColors: colors)
                    .frame(width: 80)
            }
            .padding(.horizontal, 16)
            .frame(width: 280, height: 32)
            .background(.black, in: Capsule())
            Slider(value: $level, in: 0...1) { Text("Preview Level") }
                .frame(width: 280)
        }
        .frame(maxWidth: .infinity)
    }
}
