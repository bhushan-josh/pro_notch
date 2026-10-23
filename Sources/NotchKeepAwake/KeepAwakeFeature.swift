import AppKit
import IOKit.pwr_mgt
import NotchCore
import Observation
import SwiftUI

public enum KeepAwakeDuration: Int, CaseIterable, Sendable {
    case indefinitely = 0
    case minutes15 = 15
    case minutes30 = 30
    case hour1 = 60
    case hours2 = 120
    case hours4 = 240

    var title: String {
        switch self {
        case .indefinitely: "Until Turned Off"
        case .minutes15: "15 Minutes"
        case .minutes30: "30 Minutes"
        case .hour1: "1 Hour"
        case .hours2: "2 Hours"
        case .hours4: "4 Hours"
        }
    }

    var seconds: TimeInterval? { self == .indefinitely ? nil : TimeInterval(rawValue * 60) }
}

public enum KeepAwakeSettings {
    public static let defaultDuration = SettingKey("keepAwake.defaultDuration", default: KeepAwakeDuration.indefinitely.rawValue)
    public static let keepDisplayOn = SettingKey("keepAwake.keepDisplayOn", default: true)
    public static let showHeaderButton = SettingKey("keepAwake.showHeaderButton", default: true)
    public static let showIndicator = SettingKey("keepAwake.showIndicator", default: false)
}

/// Holds a power assertion so the Mac (and optionally the display) stays awake.
@MainActor
@Observable
final class KeepAwakeManager: IdleActivityProvider {
    private(set) var isActive = false
    private(set) var endsAt: Date?
    private(set) var idleActivityUpdatedAt = Date()

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    func toggle() {
        if isActive {
            stop()
        } else {
            start(for: KeepAwakeDuration(rawValue: Defaults[KeepAwakeSettings.defaultDuration]) ?? .indefinitely)
        }
    }

    func start(for duration: KeepAwakeDuration) {
        releaseAssertion()
        let type = Defaults[KeepAwakeSettings.keepDisplayOn] ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Pro Notch Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertionID = id
        isActive = true
        idleActivityUpdatedAt = Date()
        expiryTask?.cancel()
        if let seconds = duration.seconds {
            endsAt = Date().addingTimeInterval(seconds)
            expiryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } else {
            endsAt = nil
        }
        announce()
    }

    func stop() {
        guard isActive else { return }
        releaseAssertion()
        expiryTask?.cancel()
        expiryTask = nil
        endsAt = nil
        isActive = false
        idleActivityUpdatedAt = Date()
        announce()
    }

    /// The indicator setting is read from UserDefaults, which SwiftUI does not observe.
    func settingsChanged() { idleActivityUpdatedAt = Date() }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func announce() {
        let active = isActive
        let endsAt = endsAt
        ActivityCenter.shared.present(LiveActivity(
            id: "keepAwake.toggle",
            category: .other,
            priority: .normal,
            duration: 1.6,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { CupIcon(active: active).frame(maxWidth: .infinity, alignment: .leading) },
            trailing: {
                Text(active ? (endsAt.map { Self.shortRemaining(until: $0) } ?? "On") : "Off")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(active ? .yellow : .white.opacity(0.6))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        ))
    }

    nonisolated static func shortRemaining(until date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
        return minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" : "\(minutes)m"
    }

    var idleActivity: LiveActivity? {
        guard isActive, Defaults[KeepAwakeSettings.showIndicator] else { return nil }
        return LiveActivity(
            id: "keepAwake.indicator",
            category: .other,
            priority: .idle,
            duration: nil,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { CupIcon(active: true).frame(maxWidth: .infinity, alignment: .leading) },
            trailing: { EmptyView() }
        )
    }
}

private struct CupIcon: View {
    let active: Bool

    var body: some View {
        Image(systemName: active ? "cup.and.heat.waves.fill" : "cup.and.saucer")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? .yellow : .white.opacity(0.55))
            .contentTransition(.symbolEffect(.replace))
    }
}

private struct KeepAwakeHeaderButton: View {
    let manager: KeepAwakeManager
    @State private var isHovering = false

    var body: some View {
        Button { manager.toggle() } label: {
            CupIcon(active: manager.isActive)
                .frame(width: 26, height: 24)
                .background(isHovering ? .white.opacity(0.1) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(helpText)
        .contextMenu {
            ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                Button("Keep Awake: \(duration.title)") { manager.start(for: duration) }
            }
            if manager.isActive {
                Divider()
                Button("Turn Off") { manager.stop() }
            }
        }
    }

    private var helpText: String {
        guard manager.isActive else { return "Keep Awake (right-click for durations)" }
        if let endsAt = manager.endsAt { return "Keeping awake, \(KeepAwakeManager.shortRemaining(until: endsAt)) left" }
        return "Keeping awake until turned off"
    }
}

@MainActor
public final class KeepAwakeFeature: NotchFeature {
    private let manager = KeepAwakeManager()
    private var settingsObserver: AnyObject?

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        registry.register(settingsPane: SettingsPane(id: "keepAwake", title: "Keep Awake", symbol: "cup.and.saucer.fill", color: .brown, category: .general, order: 40) {
            KeepAwakeSettingsView()
        })
        registry.register(idleProvider: manager)
        applyHeaderButton()
        settingsObserver = Defaults.observe([KeepAwakeSettings.showHeaderButton.name, KeepAwakeSettings.showIndicator.name]) { [weak self] in
            self?.applyHeaderButton()
            self?.manager.settingsChanged()
        }
    }

    public func stop() {
        manager.stop()
        NotchRegistry.shared.unregister(headerAccessoryID: "keepAwake")
        settingsObserver = nil
    }

    private func applyHeaderButton() {
        if Defaults[KeepAwakeSettings.showHeaderButton] {
            let manager = manager
            NotchRegistry.shared.register(headerAccessory: HeaderAccessory(id: "keepAwake", order: 10) {
                KeepAwakeHeaderButton(manager: manager)
            })
        } else {
            NotchRegistry.shared.unregister(headerAccessoryID: "keepAwake")
        }
    }
}

struct KeepAwakeSettingsView: View {
    @AppStorage(KeepAwakeSettings.defaultDuration) private var defaultDuration
    @AppStorage(KeepAwakeSettings.keepDisplayOn) private var keepDisplayOn
    @AppStorage(KeepAwakeSettings.showHeaderButton) private var showHeaderButton
    @AppStorage(KeepAwakeSettings.showIndicator) private var showIndicator

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Show Button in the Notch", info: "A cup button beside Settings in the expanded notch. Right-click it for durations.", isOn: $showHeaderButton)
                Picker("Default Duration", selection: $defaultDuration) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                SettingsToggle("Keep the Display On", info: "Off lets the screen sleep while the Mac itself stays awake.", isOn: $keepDisplayOn)
                SettingsToggle("Show Indicator in the Closed Notch", info: "A small cup while Keep Awake is on.", isOn: $showIndicator)
            }
        }
    }
}
