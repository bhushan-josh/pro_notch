import NotchCore
import Observation
import SwiftUI

@MainActor
@Observable
final class FocusController {
    private(set) var hasAccess = FocusStore.canRead

    @ObservationIgnored private let monitor = FocusMonitor()
    @ObservationIgnored private var hasBaseline = false

    func start() {
        ActivityCenter.shared.gate = { activity in
            MainActor.assumeIsolated { FocusGate.allows(activity) }
        }
        monitor.onReading = { [weak self] reading in self?.apply(reading) }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        monitor.onReading = nil
        ActivityCenter.shared.gate = nil
    }

    private func apply(_ reading: FocusReading?) {
        let readable = reading != nil
        if hasAccess != readable { hasAccess = readable }
        guard let reading else { return }

        let status = SystemStatus.shared
        let info = reading.activeIdentifier.map { FocusCatalog.info(for: $0, config: reading.configs[$0]) }

        // The first reading is the state at launch, not a change worth announcing.
        guard hasBaseline else {
            hasBaseline = true
            if status.focus != info { status.focus = info }
            return
        }
        guard info != status.focus else { return }
        let previous = status.focus
        status.focus = info

        guard Defaults[FocusSettings.enabled] else { return }
        if let info {
            if info.identifier == FocusCatalog.sleepIdentifier, previous?.identifier != info.identifier,
               Defaults[FocusSettings.playSoundOnSleepFocus] {
                SystemSound.focus.play()
            }
            ActivityCenter.shared.present(FocusActivity.make(info, isOn: true))
        } else if let previous {
            ActivityCenter.shared.present(FocusActivity.make(previous, isOn: false))
        }
    }
}

@MainActor
enum FocusGate {
    static func allows(_ activity: LiveActivity) -> Bool {
        guard SystemStatus.shared.focus != nil else { return true }
        switch activity.category {
        case .volume: return Defaults[FocusSettings.allowVolumeWhenFocused]
        case .brightness, .keyboardBacklight: return Defaults[FocusSettings.allowBrightnessWhenFocused]
        case .battery: return activity.id == "battery.low" || Defaults[FocusSettings.allowBatteryWhenFocused]
        case .connectivity: return Defaults[FocusSettings.allowConnectivityWhenFocused]
        default: return true
        }
    }
}

@MainActor
enum FocusActivity {
    static let id = "focus"
    private static let maxNameWidth: CGFloat = 120

    static func make(_ info: FocusModeInfo, isOn: Bool) -> LiveActivity {
        let state = isOn ? "On" : "Off"
        let nameWidth = WingText.width(info.name)
        let showsName = nameWidth <= maxNameWidth
        let symbolColor: Color = isOn ? info.color : .white.opacity(0.45)

        return LiveActivity(
            id: id,
            category: .focus,
            priority: .normal,
            duration: Defaults[FocusSettings.duration],
            leadingWidth: 18 + (showsName ? 5 + nameWidth : 0),
            trailingWidth: WingText.width(state),
            leading: {
                LeadingWing {
                    Image(systemName: info.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(symbolColor)
                        .frame(width: 18)
                    if showsName {
                        Text(info.name).font(WingText.font).lineLimit(1)
                            .foregroundStyle(isOn ? .white : .white.opacity(0.6))
                    }
                }
            },
            trailing: {
                TrailingWing {
                    Text(state).font(WingText.font)
                        .foregroundStyle(isOn ? info.color : .white.opacity(0.6))
                }
            }
        )
    }
}
