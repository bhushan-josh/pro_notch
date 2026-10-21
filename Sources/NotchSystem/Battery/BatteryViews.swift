import NotchCore
import SwiftUI

@MainActor
enum BatteryActivities {
    static let powerID = "battery.power"
    static let lowBatteryID = "battery.low"
    static let lowPowerModeID = "battery.lowPowerMode"

    private static var hidePercentage: Bool { Defaults[BatterySettings.hidePercentage] }

    static func power(_ snapshot: BatterySnapshot, isLowPowerMode: Bool) -> LiveActivity {
        let charged = snapshot.isCharged || (snapshot.isPluggedIn && snapshot.percentage >= 100)
        let label: String
        let symbol: String
        let symbolColor: Color
        if snapshot.isPluggedIn {
            label = charged ? "Charged" : snapshot.isCharging ? "Charging" : "Plugged In"
            symbol = "bolt.fill"
            symbolColor = .green
        } else {
            label = "On Battery"
            symbol = "bolt.slash.fill"
            symbolColor = .white.opacity(0.6)
        }

        var detail: String?
        if !snapshot.isPluggedIn, let minutes = snapshot.minutesToEmpty {
            detail = DurationText.minutes(minutes)
        } else if !hidePercentage {
            detail = "\(snapshot.percentage)%"
        }

        let fill = fillColor(snapshot, isLowPowerMode: isLowPowerMode)
        return LiveActivity(
            id: powerID,
            category: .battery,
            priority: .normal,
            duration: Defaults[CoreSettings.activityDuration],
            leadingWidth: 14 + 5 + WingText.width(label),
            trailingWidth: trailingWidth(detail),
            leading: {
                LeadingWing {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(symbolColor)
                        .frame(width: 14)
                    Text(label).font(WingText.font).lineLimit(1)
                }
            },
            trailing: {
                TrailingWing {
                    if let detail {
                        Text(detail).font(WingText.font).monospacedDigit().lineLimit(1)
                            .foregroundStyle(snapshot.isPluggedIn ? .green : .white)
                    }
                    BatteryGlyph(level: snapshot.level, tint: fill)
                }
            }
        )
    }

    static func lowBattery(_ snapshot: BatterySnapshot) -> LiveActivity {
        let label = "Low Battery"
        let detail = hidePercentage ? nil : "\(snapshot.percentage)%"
        return LiveActivity(
            id: lowBatteryID,
            category: .battery,
            priority: .high,
            duration: max(Defaults[CoreSettings.activityDuration], 3),
            leadingWidth: 14 + 5 + WingText.width(label),
            trailingWidth: trailingWidth(detail),
            leading: {
                LeadingWing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 14)
                    Text(label).font(WingText.font).lineLimit(1)
                }
                .foregroundStyle(.red)
            },
            trailing: {
                TrailingWing {
                    if let detail {
                        Text(detail).font(WingText.font).monospacedDigit().foregroundStyle(.red)
                    }
                    BatteryGlyph(level: snapshot.level, tint: .red, frameColor: .red.opacity(0.6))
                }
            }
        )
    }

    static func lowPowerMode(enabled: Bool, snapshot: BatterySnapshot) -> LiveActivity {
        let label = "Low Power"
        let state = enabled ? "On" : "Off"
        let level = snapshot.hasBattery ? snapshot.level : 1
        return LiveActivity(
            id: lowPowerModeID,
            category: .battery,
            priority: .normal,
            duration: Defaults[CoreSettings.activityDuration],
            leadingWidth: BatteryGlyph.totalWidth + 5 + WingText.width(label),
            trailingWidth: WingText.width(state),
            leading: {
                LeadingWing {
                    BatteryGlyph(level: level, tint: enabled ? .yellow : .white)
                    Text(label).font(WingText.font).lineLimit(1)
                }
            },
            trailing: {
                TrailingWing {
                    Text(state).font(WingText.font)
                        .foregroundStyle(enabled ? .yellow : .white.opacity(0.6))
                }
            }
        )
    }

    static func fillColor(_ snapshot: BatterySnapshot, isLowPowerMode: Bool) -> Color {
        if snapshot.isPluggedIn { return .green }
        if snapshot.percentage <= Defaults[BatterySettings.lowBatteryThreshold] { return .red }
        if isLowPowerMode { return .yellow }
        return .white
    }

    private static func trailingWidth(_ detail: String?) -> CGFloat {
        BatteryGlyph.totalWidth + (detail.map { WingText.width($0) + 5 } ?? 0)
    }
}
