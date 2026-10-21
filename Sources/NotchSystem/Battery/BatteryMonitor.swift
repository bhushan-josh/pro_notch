import Foundation
import IOKit.ps
import Observation

struct BatterySnapshot: Equatable, Sendable {
    var hasBattery: Bool
    var percentage: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isCharged: Bool
    var minutesToFull: Int?
    var minutesToEmpty: Int?

    var level: Double { Double(percentage) / 100 }

    static let none = BatterySnapshot(
        hasBattery: false, percentage: 100, isCharging: false, isPluggedIn: true,
        isCharged: false, minutesToFull: nil, minutesToEmpty: nil
    )
}

@MainActor
@Observable
final class BatteryMonitor {
    private(set) var snapshot = BatterySnapshot.none
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored var onChange: ((_ old: BatterySnapshot, _ new: BatterySnapshot) -> Void)?
    @ObservationIgnored var onLowPowerModeChange: ((Bool) -> Void)?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?

    func start() {
        guard runLoopSource == nil else { return }
        snapshot = Self.read()
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // The context is unretained; BatteryController owns this monitor and calls stop() before releasing it.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLowPowerMode() }
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let powerStateObserver { NotificationCenter.default.removeObserver(powerStateObserver) }
        powerStateObserver = nil
    }

    private func refresh() {
        let new = Self.read()
        guard new != snapshot else { return }
        let old = snapshot
        snapshot = new
        onChange?(old, new)
    }

    private func refreshLowPowerMode() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard enabled != isLowPowerMode else { return }
        isLowPowerMode = enabled
        onLowPowerModeChange?(enabled)
    }

    nonisolated static func read() -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool ?? true
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percentage = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let pluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let charged = description[kIOPSIsChargedKey] as? Bool ?? (pluggedIn && percentage >= 100)

            // IOKit reports -1 while it is still estimating.
            func minutes(_ key: String) -> Int? {
                guard let value = description[key] as? Int, value > 0 else { return nil }
                return value
            }

            return BatterySnapshot(
                hasBattery: true,
                percentage: min(max(percentage, 0), 100),
                isCharging: charging,
                isPluggedIn: pluggedIn,
                isCharged: charged,
                minutesToFull: charging ? minutes(kIOPSTimeToFullChargeKey) : nil,
                minutesToEmpty: pluggedIn ? nil : minutes(kIOPSTimeToEmptyKey)
            )
        }
        return .none
    }
}
