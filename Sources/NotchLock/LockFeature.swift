import SwiftUI
import NotchCore

@MainActor
public final class LockFeature: NotchFeature {
    private let monitor = LockMonitor()
    private let activity = LockActivityController()
    private let window = LockScreenWindowController()
    private let keepAwake = KeepAwake()
    private let weather = WeatherManager()
    private var loops: [ObservationLoop] = []
    private var settingsObserver: AnyObject?

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        registry.register(settingsPane: SettingsPane(id: "lockScreen", title: "Lock Screen", symbol: "lock.fill", color: .teal, order: 70) {
            [weather, window] in
            LockSettingsView(weather: weather, onPreview: { window.preview() })
        })
        registry.register(lockScreenWidget: WeatherWidget.make())
        registry.register(permission: weather.permission)

        monitor.onEvent = { [weak self] event in self?.handle(event) }
        window.start()
        weather.start()
        monitor.start()

        loops.append(ObservationLoop { [weak self] in self?.window.update() })
        loops.append(ObservationLoop { [weak self] in self?.updateKeepAwake() })
        settingsObserver = Defaults.observe([LockSettings.keepAwake.name]) { [weak self] in self?.updateKeepAwake() }
    }

    public func stop() {
        loops.forEach { $0.cancel() }
        loops.removeAll()
        settingsObserver = nil
        monitor.stop()
        window.stop()
        weather.stop()
        keepAwake.set(false)
        activity.dismiss()
        NotchRegistry.shared.unregister(lockScreenWidgetID: WeatherWidget.id)
    }

    private func handle(_ event: LockMonitor.Event) {
        switch event {
        case .locked:
            activity.showLocked()
        case .unlocked:
            activity.showUnlocked()
            weather.refresh()
        case .screenSaverStarted, .screenSaverStopped:
            break
        }
    }

    private func updateKeepAwake() {
        let status = SystemStatus.shared
        keepAwake.set(Defaults[LockSettings.keepAwake] && status.isScreenLocked && status.isMediaPlaying)
    }
}
