import NotchCore
import SwiftUI

@MainActor
final class BatteryController {
    let monitor = BatteryMonitor()
    /// Low battery levels already announced during the current discharge.
    private var announcedLevels = Set<Int>()

    func start() {
        monitor.onChange = { [weak self] old, new in self?.handle(old: old, new: new) }
        monitor.onLowPowerModeChange = { [weak self] enabled in self?.lowPowerModeChanged(enabled) }
        monitor.start()
        if monitor.snapshot.hasBattery, !monitor.snapshot.isPluggedIn {
            checkLowBattery(monitor.snapshot)
        }
    }

    func stop() {
        monitor.stop()
        monitor.onChange = nil
        monitor.onLowPowerModeChange = nil
    }

    private func handle(old: BatterySnapshot, new: BatterySnapshot) {
        guard new.hasBattery, old.hasBattery else { return }
        let center = ActivityCenter.shared

        if new.isPluggedIn != old.isPluggedIn {
            if new.isPluggedIn {
                announcedLevels.removeAll()
                center.dismiss(id: BatteryActivities.lowBatteryID)
                if Defaults[BatterySettings.playSoundOnCharge] { SystemSound.charging.play() }
            }
            presentPower(new)
        } else if new.isPluggedIn, new.isCharged, !old.isCharged {
            presentPower(new)
        } else if center.isPresented(id: BatteryActivities.powerID) {
            // Keeps the open activity current, e.g. when the time estimate arrives after unplugging.
            presentPower(new)
        }

        if !new.isPluggedIn { checkLowBattery(new) }
    }

    private func presentPower(_ snapshot: BatterySnapshot) {
        guard Defaults[BatterySettings.showPowerActivity] else { return }
        ActivityCenter.shared.present(BatteryActivities.power(snapshot, isLowPowerMode: monitor.isLowPowerMode))
    }

    private func checkLowBattery(_ snapshot: BatterySnapshot) {
        let threshold = Defaults[BatterySettings.lowBatteryThreshold]
        let levels = Set([threshold, 10, 5].filter { $0 <= threshold })
        // Small hysteresis so a reading wobbling around a level does not re-announce it.
        announcedLevels = announcedLevels.filter { snapshot.percentage <= $0 + 2 }
        let crossed = levels.filter { snapshot.percentage <= $0 }
        guard !crossed.subtracting(announcedLevels).isEmpty else { return }
        announcedLevels.formUnion(crossed)

        guard Defaults[BatterySettings.warnOnLowBattery] else { return }
        if Defaults[BatterySettings.playSoundOnLowBattery] { SystemSound.lowBattery.play() }
        ActivityCenter.shared.present(BatteryActivities.lowBattery(snapshot))
    }

    private func lowPowerModeChanged(_ enabled: Bool) {
        guard Defaults[BatterySettings.notifyOnLowPowerMode] else { return }
        ActivityCenter.shared.present(BatteryActivities.lowPowerMode(enabled: enabled, snapshot: monitor.snapshot))
    }
}
