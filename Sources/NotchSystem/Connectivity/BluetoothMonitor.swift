import CoreBluetooth
import IOBluetooth
import NotchCore

/// Bluetooth connect and disconnect events. IOBluetooth calls the selectors on its own queue on recent macOS
/// (the main run loop on older releases), so each hops to the main actor before touching any state.
@MainActor
final class BluetoothMonitor: NSObject {
    var onConnect: ((_ device: IOBluetoothDevice, _ isInitial: Bool) -> Void)?
    var onDisconnect: ((IOBluetoothDevice) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var startedAt = Date.distantPast

    func start() {
        guard connectNotification == nil else { return }
        startedAt = Date()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
    }

    @objc nonisolated private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let device = device
        Task { @MainActor [weak self] in self?.handleConnected(device) }
    }

    private func handleConnected(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        // Registering replays a connect for every device that is already connected; those are not news.
        onConnect?(device, Date().timeIntervalSince(startedAt) < 2)
    }

    @objc nonisolated private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        nonisolated(unsafe) let notification = notification
        nonisolated(unsafe) let device = device
        Task { @MainActor [weak self] in self?.handleDisconnected(notification, device: device) }
    }

    private func handleDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectNotifications.removeValue(forKey: address) }
        onDisconnect?(device)
    }
}

/// Bluetooth access is a TCC permission; IOBluetooth calls trigger the same prompt as CoreBluetooth.
@MainActor
final class BluetoothAuthorizer: NSObject, CBCentralManagerDelegate {
    static let shared = BluetoothAuthorizer()

    private var manager: CBCentralManager?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    static var status: PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static var requirement: PermissionRequirement {
        PermissionRequirement(
            id: "bluetooth",
            title: "Bluetooth",
            description: "Show when headphones, keyboards and other devices connect, with their battery level.",
            symbol: "airpodspro",
            settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"),
            status: { status },
            request: { await shared.request() }
        )
    }

    func request() async {
        guard CBManager.authorization == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if manager == nil {
                manager = CBCentralManager(delegate: self, queue: .main)
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.resumeWaiters()
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            guard CBManager.authorization != .notDetermined else { return }
            resumeWaiters()
        }
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
