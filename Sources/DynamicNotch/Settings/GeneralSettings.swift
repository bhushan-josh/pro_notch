import AppKit
import NotchCore
import ServiceManagement
import SwiftUI

@MainActor
enum GeneralSettings {
    static func registerPanes() {
        let registry = NotchRegistry.shared
        registry.register(settingsPane: SettingsPane(id: "general", title: "General", symbol: "gearshape.fill", color: .gray, category: .general, order: 0) {
            GeneralSettingsView()
        })
        registry.register(settingsPane: SettingsPane(id: "permissions", title: "Permissions", symbol: "hand.raised.fill", color: .blue, category: .app, order: 900) {
            PermissionsSettingsView()
        })
        registry.register(settingsPane: SettingsPane(id: "about", title: "About", symbol: "info.circle.fill", color: .secondary, category: .app, order: 1000) {
            AboutSettingsView()
        })
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(CoreSettings.displayTarget) private var displayTarget
    @AppStorage(CoreSettings.specificDisplayUUID) private var specificDisplay
    @AppStorage(CoreSettings.forceSimulatedNotch) private var forceSimulatedNotch
    @AppStorage(CoreSettings.expandOnHover) private var expandOnHover
    @AppStorage(CoreSettings.hoverDuration) private var hoverDuration
    @AppStorage(CoreSettings.haptics) private var haptics
    @AppStorage(CoreSettings.contrastOutline) private var contrastOutline
    @AppStorage(CoreSettings.swipeToToggle) private var swipeToToggle
    @AppStorage(CoreSettings.swipeToDismiss) private var swipeToDismiss
    @AppStorage(CoreSettings.swipeToSkip) private var swipeToSkip
    @AppStorage(CoreSettings.swipeToCycleActivity) private var swipeToCycle
    @AppStorage(CoreSettings.naturalMovement) private var naturalMovement
    @AppStorage(CoreSettings.expandedHome) private var expandedHome
    @AppStorage(CoreSettings.idleMostRecent) private var idleMostRecent
    @AppStorage(CoreSettings.activityDuration) private var activityDuration
    @AppStorage(CoreSettings.hideInFullscreen) private var hideInFullscreen
    @AppStorage(CoreSettings.hideInMissionControl) private var hideInMissionControl
    @AppStorage(CoreSettings.hideFromScreenCapture) private var hideFromScreenCapture
    @AppStorage(CoreSettings.hideMenuBarIcon) private var hideMenuBarIcon
    @AppStorage(CoreSettings.showOnLockScreen) private var showOnLockScreen
    @AppStorage(CoreSettings.notchWidthOffset) private var notchWidth
    @AppStorage(CoreSettings.notchHeightOffset) private var notchHeight

    var body: some View {
        SettingsPaneView {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in LaunchAtLogin.set(enabled) }
                Picker("Display On", selection: $displayTarget) {
                    ForEach(DisplayTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if displayTarget == .specific {
                    Picker("Display", selection: $specificDisplay) {
                        ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                            Text(screen.localizedName).tag(screen.displayUUID)
                        }
                    }
                }
            }

            Section("Behaviour") {
                SettingsToggle("Expand on Hover", info: "Open the notch when the pointer rests on it.", isOn: $expandOnHover)
                if expandOnHover {
                    SettingsSlider("Hover Duration", value: $hoverDuration, in: 0...1.5, step: 0.05, format: { String(format: "%.2fs", $0) })
                }
                Toggle("Haptic Feedback", isOn: $haptics)
                Toggle("Contrast Outline", isOn: $contrastOutline)
                SettingsSlider("Activity Duration", value: $activityDuration, in: 1...6, step: 0.5)
            }

            Section("Gestures") {
                Toggle("Swipe to Open and Close", isOn: $swipeToToggle)
                SettingsToggle("Swipe Up to Dismiss", info: "Swipe up on an activity to hide it.", isOn: $swipeToDismiss)
                Toggle("Swipe Sideways to Skip Tracks", isOn: $swipeToSkip)
                SettingsToggle("Swipe Sideways to Cycle Activities", info: "Used when nothing is playing.", isOn: $swipeToCycle)
                Toggle("Natural Movement", isOn: $naturalMovement)
            }

            Section("Idle Activity") {
                Picker("Expanded View", selection: $expandedHome) {
                    ForEach(ExpandedHome.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Prefer Most Recent Activity", isOn: $idleMostRecent)
            }

            Section("Visibility") {
                Toggle("Hide in Fullscreen", isOn: $hideInFullscreen)
                Toggle("Hide in Mission Control", isOn: $hideInMissionControl)
                Toggle("Hide from Screen Capture", isOn: $hideFromScreenCapture)
                Toggle("Show on Lock Screen", isOn: $showOnLockScreen)
                Toggle("Hide Menu Bar Icon", isOn: $hideMenuBarIcon)
            }

            Section("Tuning") {
                SettingsSlider("Notch Width", value: $notchWidth, in: -40...40, step: 1, format: { String(format: "%+.0f", $0) })
                SettingsSlider("Notch Height", value: $notchHeight, in: -10...10, step: 1, format: { String(format: "%+.0f", $0) })
                SettingsToggle("Force Simulated Notch", info: "Draw a notch on displays that do not have one.", isOn: $forceSimulatedNotch)
            }
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
    }
}

struct PermissionsSettingsView: View {
    private let registry = NotchRegistry.shared
    @State private var refresh = 0

    var body: some View {
        SettingsPaneView {
            Section {
                ForEach(registry.permissions) { permission in
                    PermissionRow(permission: permission, refresh: $refresh)
                }
            } footer: {
                Text("Ad-hoc signed builds get a new identity on every rebuild, so macOS may ask again after updating.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }
}

struct PermissionRow: View {
    let permission: PermissionRequirement
    @Binding var refresh: Int

    var body: some View {
        let status = permission.status()
        HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                Text(permission.description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("Allow") { Task { await permission.request(); refresh += 1 } }
            case .denied:
                Button("Open Settings") {
                    if let url = permission.settingsURL { NSWorkspace.shared.open(url) }
                }
            }
        }
        .id(refresh)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Dynamic Notch").font(.largeTitle.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A personal Dynamic Island for the Mac notch.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
