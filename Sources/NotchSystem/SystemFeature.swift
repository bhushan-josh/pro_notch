import NotchCore
import SwiftUI

@MainActor
public final class SystemFeature: NotchFeature {
    private let battery = BatteryController()
    private let connectivity = ConnectivityController()
    private let focus = FocusController()

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        let battery = battery, connectivity = connectivity, focus = focus

        registry.register(settingsPane: SettingsPane(id: "battery", title: "Battery", symbol: "battery.100percent.bolt", color: .green, category: .notifications, order: 30) {
            BatterySettingsView(monitor: battery.monitor)
        })
        registry.register(settingsPane: SettingsPane(id: "connectivity", title: "Connectivity", symbol: "airpodspro", color: .blue, category: .notifications, order: 40) {
            ConnectivitySettingsView(controller: connectivity)
        })
        registry.register(settingsPane: SettingsPane(id: "focus", title: "Focus", symbol: "moon.fill", color: .indigo, category: .notifications, order: 50) {
            FocusSettingsView(controller: focus)
        })

        registry.register(permission: BluetoothAuthorizer.requirement)
        registry.register(permission: FocusStore.requirement)

        battery.start()
        connectivity.start()
        focus.start()
    }

    public func stop() {
        battery.stop()
        connectivity.stop()
        focus.stop()
    }
}
