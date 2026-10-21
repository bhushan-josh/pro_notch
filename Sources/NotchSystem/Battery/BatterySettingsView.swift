import NotchCore
import SwiftUI

struct BatterySettingsView: View {
    let monitor: BatteryMonitor

    @AppStorage(BatterySettings.showPowerActivity) private var showPowerActivity
    @AppStorage(BatterySettings.playSoundOnCharge) private var playSoundOnCharge
    @AppStorage(BatterySettings.hidePercentage) private var hidePercentage
    @AppStorage(BatterySettings.warnOnLowBattery) private var warnOnLowBattery
    @AppStorage(BatterySettings.lowBatteryThreshold) private var lowBatteryThreshold
    @AppStorage(BatterySettings.playSoundOnLowBattery) private var playSoundOnLowBattery
    @AppStorage(BatterySettings.notifyOnLowPowerMode) private var notifyOnLowPowerMode

    var body: some View {
        let snapshot = monitor.snapshot
        SettingsPaneView {
            if snapshot.hasBattery {
                Section {
                    LabeledContent("Battery") {
                        HStack(spacing: 8) {
                            Text(statusText(snapshot)).foregroundStyle(.secondary)
                            BatteryGlyph(
                                level: snapshot.level,
                                tint: BatteryActivities.fillColor(snapshot, isLowPowerMode: monitor.isLowPowerMode),
                                frameColor: .secondary
                            )
                        }
                    }
                }

                Section("Power") {
                    SettingsToggle("Show Power Activity", info: "Show the charge level when power is connected or disconnected.", isOn: $showPowerActivity)
                    Toggle("Play Sound When Charging", isOn: $playSoundOnCharge)
                    Toggle("Hide Percentage", isOn: $hidePercentage)
                }

                Section("Low Battery") {
                    SettingsToggle("Warn on Low Battery", info: "Warns once when crossing the threshold, then again at 10% and 5%.", isOn: $warnOnLowBattery)
                    if warnOnLowBattery {
                        SettingsSlider("Threshold", value: thresholdBinding, in: 5...50, step: 1, format: { "\(Int($0))%" })
                        Toggle("Play Sound", isOn: $playSoundOnLowBattery)
                    }
                }
            }

            Section {
                SettingsToggle("Notify on Low Power Mode", info: "Show when Low Power Mode turns on or off.", isOn: $notifyOnLowPowerMode)
            } header: {
                Text("Low Power Mode")
            } footer: {
                if !snapshot.hasBattery {
                    Text("This Mac has no internal battery, so only Low Power Mode changes are shown.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(get: { Double(lowBatteryThreshold) }, set: { lowBatteryThreshold = Int($0.rounded()) })
    }

    private func statusText(_ snapshot: BatterySnapshot) -> String {
        var parts = ["\(snapshot.percentage)%"]
        if snapshot.isPluggedIn {
            if snapshot.isCharged {
                parts.append("Charged")
            } else if snapshot.isCharging {
                parts.append(snapshot.minutesToFull.map { "\(DurationText.minutes($0)) until full" } ?? "Charging")
            } else {
                parts.append("Not Charging")
            }
        } else if let minutes = snapshot.minutesToEmpty {
            parts.append("\(DurationText.minutes(minutes)) remaining")
        }
        if monitor.isLowPowerMode { parts.append("Low Power Mode") }
        return parts.joined(separator: " · ")
    }
}
