import IOBluetooth
import NotchCore
import Observation
import SwiftUI

struct BluetoothDeviceInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var appearance: DeviceAppearance
    var battery: DeviceBattery
}

@MainActor
@Observable
final class ConnectivityController {
    private(set) var devices: [BluetoothDeviceInfo] = []
    private(set) var isAuthorized = BluetoothAuthorizer.status == .granted

    @ObservationIgnored private let monitor = BluetoothMonitor()
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var batteryTasks: [String: Task<Void, Never>] = [:]

    func start() {
        monitor.onConnect = { [weak self] device, isInitial in self?.connected(device, isInitial: isInitial) }
        monitor.onDisconnect = { [weak self] device in self?.disconnected(device) }
        startWhenAuthorized()
    }

    func stop() {
        authorizationTask?.cancel()
        authorizationTask = nil
        removeActivationObserver()
        batteryTasks.values.forEach { $0.cancel() }
        batteryTasks.removeAll()
        monitor.stop()
        devices.removeAll()
    }

    /// Touching IOBluetooth before access is granted would raise the system prompt outside onboarding.
    /// A denial only changes in System Settings, so it is rechecked when the app is next activated.
    private func startWhenAuthorized() {
        authorizationTask?.cancel()
        authorizationTask = nil
        switch BluetoothAuthorizer.status {
        case .granted:
            removeActivationObserver()
            isAuthorized = true
            monitor.start()
        case .notDetermined:
            authorizationTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, let self else { return }
                    if BluetoothAuthorizer.status != .notDetermined {
                        self.startWhenAuthorized()
                        return
                    }
                }
            }
        case .denied:
            guard activationObserver == nil else { return }
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.startWhenAuthorized() }
            }
        }
    }

    private func removeActivationObserver() {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    private func info(for device: IOBluetoothDevice, address: String) -> BluetoothDeviceInfo {
        BluetoothDeviceInfo(
            id: address,
            name: device.name ?? "Bluetooth Device",
            appearance: DeviceSymbols.appearance(for: device),
            battery: BluetoothBattery.read(device)
        )
    }

    private func connected(_ device: IOBluetoothDevice, isInitial: Bool) {
        guard let address = device.addressString.map(BluetoothBattery.normalize) else { return }
        let info = info(for: device, address: address)
        upsert(info)
        watchBattery(device, address: address, presentUpdates: !isInitial)

        guard !isInitial, Defaults[ConnectivitySettings.enabled] else { return }
        if Defaults[ConnectivitySettings.playSound] { SystemSound.connect.play() }
        present(info, connected: true)
    }

    private func disconnected(_ device: IOBluetoothDevice) {
        guard let address = device.addressString.map(BluetoothBattery.normalize) else { return }
        batteryTasks.removeValue(forKey: address)?.cancel()
        let known = devices.first { $0.id == address }
        devices.removeAll { $0.id == address }

        guard Defaults[ConnectivitySettings.enabled] else { return }
        var info = known ?? info(for: device, address: address)
        info.battery = DeviceBattery()
        present(info, connected: false)
    }

    /// Buds report their levels a moment after connecting, then drift; poll briefly, then slowly.
    /// Devices that report nothing during the burst have no battery to show, so they are left alone.
    private func watchBattery(_ device: IOBluetoothDevice, address: String, presentUpdates: Bool) {
        batteryTasks[address]?.cancel()
        let hasBattery = devices.first { $0.id == address }.map { !$0.battery.isEmpty } ?? false
        batteryTasks[address] = Task { [weak self] in
            let burst: [Double] = [1, 1.5, 2, 3]
            var reported = hasBattery
            var index = 0
            while !Task.isCancelled {
                if index < burst.count {
                    try? await Task.sleep(for: .seconds(burst[index]))
                } else {
                    guard reported else { return }
                    try? await Task.sleep(for: .seconds(300), tolerance: .seconds(60))
                }
                index += 1
                guard !Task.isCancelled, let self, device.isConnected() else { return }
                let battery = BluetoothBattery.read(device)
                if !battery.isEmpty { reported = true }
                guard let current = self.devices.first(where: { $0.id == address }), current.battery != battery else { continue }
                var updated = current
                updated.battery = battery
                self.upsert(updated)
                if presentUpdates, ActivityCenter.shared.isPresented(id: Self.activityID(address)) {
                    self.present(updated, connected: true)
                }
            }
        }
    }

    private func upsert(_ info: BluetoothDeviceInfo) {
        if let index = devices.firstIndex(where: { $0.id == info.id }) {
            devices[index] = info
        } else {
            devices.append(info)
        }
    }

    private func present(_ info: BluetoothDeviceInfo, connected: Bool) {
        ActivityCenter.shared.present(ConnectivityActivities.make(
            info,
            id: Self.activityID(info.id),
            connected: connected,
            showBattery: Defaults[ConnectivitySettings.showBattery],
            style: Defaults[ConnectivitySettings.style]
        ))
    }

    static func activityID(_ address: String) -> String { "connectivity.\(address)" }
}
