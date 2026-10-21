import NotchCore
import SwiftUI

@MainActor
enum ConnectivityActivities {
    static func make(_ info: BluetoothDeviceInfo, id: String, connected: Bool, showBattery: Bool, style: ConnectivityStyle) -> LiveActivity {
        let level = connected && showBattery ? info.battery.primary : nil
        let status = connected ? "Connected" : "Disconnected"
        let trailingWidth = level.map { WingText.width("\($0)%") + 5 + BatteryGlyph.totalWidth } ?? WingText.width(status)
        let symbol = info.appearance.symbol

        let activity = LiveActivity(
            id: id,
            category: .connectivity,
            priority: .normal,
            duration: Defaults[CoreSettings.activityDuration],
            leadingWidth: 24,
            trailingWidth: trailingWidth,
            leading: {
                LeadingWing {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(connected ? .white : .white.opacity(0.5))
                        .frame(width: 24)
                }
            },
            trailing: {
                TrailingWing {
                    if let level {
                        Text("\(level)%").font(WingText.font).monospacedDigit()
                        BatteryGlyph(level: Double(level) / 100, tint: level <= 20 ? .red : .green)
                    } else {
                        Text(status).font(WingText.font).lineLimit(1)
                            .foregroundStyle(connected ? .white : .white.opacity(0.6))
                    }
                }
            }
        )

        let components = connected && showBattery && info.battery.hasComponents ? info.battery : nil
        switch style {
        case .symbol:
            return activity.withBottom(height: 26) {
                DeviceStrip(name: info.name, appearance: info.appearance, battery: components)
            }
        case .threeDimensional:
            return activity.withBottom(height: 62) {
                DeviceShowcase(info: info, connected: connected, battery: components)
            }
        }
    }
}

private struct DeviceStrip: View {
    let name: String
    let appearance: DeviceAppearance
    let battery: DeviceBattery?

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let battery {
                ComponentLevels(appearance: appearance, battery: battery)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
    }
}

private struct ComponentLevels: View {
    let appearance: DeviceAppearance
    let battery: DeviceBattery

    var body: some View {
        HStack(spacing: 8) {
            if let left = battery.left {
                level(symbol: appearance.leftSymbol, label: "L", value: left)
            }
            if let right = battery.right {
                level(symbol: appearance.rightSymbol, label: "R", value: right)
            }
            if let caseLevel = battery.caseLevel {
                level(symbol: appearance.caseSymbol, label: "Case", value: caseLevel)
            }
        }
    }

    private func level(symbol: String?, label: String, value: Int) -> some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .medium))
            } else {
                Text(label).font(.system(size: 10, weight: .bold))
            }
            Text("\(value)%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(value <= 20 ? .red : .white.opacity(0.85))
        }
        .foregroundStyle(.white.opacity(0.6))
    }
}

/// Stand-in for a 3D device render: a large symbol that swings gently with a soft glow.
private struct DeviceShowcase: View {
    let info: BluetoothDeviceInfo
    let connected: Bool
    let battery: DeviceBattery?

    @State private var appeared = false
    @State private var swing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: info.appearance.symbol)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(connected ? .white : .white.opacity(0.45))
                .shadow(color: .white.opacity(connected ? 0.45 : 0), radius: 8)
                .rotation3DEffect(.degrees(swing ? 18 : -18), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let battery {
                    ComponentLevels(appearance: info.appearance, battery: battery)
                } else {
                    Text(connected ? "Connected" : "Disconnected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            guard connected else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { swing = true }
        }
    }
}
