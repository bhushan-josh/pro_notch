import NotchCore
import SwiftUI

struct ConnectivitySettingsView: View {
    let controller: ConnectivityController

    @AppStorage(ConnectivitySettings.enabled) private var enabled
    @AppStorage(ConnectivitySettings.showBattery) private var showBattery
    @AppStorage(ConnectivitySettings.playSound) private var playSound
    @AppStorage(ConnectivitySettings.style) private var style

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Show Bluetooth Devices", info: "Show when a Bluetooth device connects or disconnects.", isOn: $enabled)
            }

            if enabled {
                Section("Appearance") {
                    Picker("Style", selection: $style) {
                        ForEach(ConnectivityStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    SettingsToggle("Show Battery Level", info: "AirPods show each bud and the case when available.", isOn: $showBattery)
                    Toggle("Play Sound on Connect", isOn: $playSound)
                }
            }

            Section("Connected Devices") {
                if !controller.isAuthorized {
                    HStack {
                        Text("Bluetooth access is required.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow") {
                            Task {
                                await BluetoothAuthorizer.shared.request()
                                if BluetoothAuthorizer.status == .denied,
                                   let url = BluetoothAuthorizer.requirement.settingsURL {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                } else if controller.devices.isEmpty {
                    Text("No devices connected.").foregroundStyle(.secondary)
                } else {
                    ForEach(controller.devices) { device in
                        DeviceRow(device: device)
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: BluetoothDeviceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.appearance.symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            Text(device.name)
            Spacer()
            Text(batteryText).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var batteryText: String {
        let battery = device.battery
        if battery.hasComponents {
            var parts: [String] = []
            if let left = battery.left { parts.append("L \(left)%") }
            if let right = battery.right { parts.append("R \(right)%") }
            if let caseLevel = battery.caseLevel { parts.append("Case \(caseLevel)%") }
            return parts.joined(separator: "  ")
        }
        return battery.primary.map { "\($0)%" } ?? ""
    }
}
