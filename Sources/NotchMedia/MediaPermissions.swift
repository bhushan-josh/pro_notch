import AppKit
import CoreServices
import NotchCore

@MainActor
enum MediaPermissions {
    private static let automationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    private static let audioCaptureURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    private static var lastKnown: [String: PermissionStatus] = [:]

    static func register() {
        let registry = NotchRegistry.shared
        let apps: [(name: String, bundleID: String, symbol: String)] = [
            ("Music", MusicBackend.bundleID, "music.note"),
            ("Spotify", SpotifyBackend.bundleID, "beats.headphones"),
        ]
        for app in apps where app.bundleID == MusicBackend.bundleID || isInstalled(app.bundleID) {
            registry.register(permission: PermissionRequirement(
                id: "media.automation.\(app.name.lowercased())",
                title: "Control \(app.name)",
                description: "Show and control what is playing in \(app.name).",
                symbol: app.symbol,
                settingsURL: automationURL,
                status: { automationStatus(bundleID: app.bundleID) },
                request: { await requestAutomation(bundleID: app.bundleID) }
            ))
        }
        registry.register(permission: PermissionRequirement(
            id: "media.audioCapture",
            title: "Audio Capture",
            description: "Listen to system audio to draw the live waveform.",
            symbol: "waveform",
            settingsURL: audioCaptureURL,
            status: { Defaults[MediaSettings.audioCaptureConfirmed] ? .granted : .notDetermined },
            request: { await LiveWaveform.shared.requestPermission() }
        ))
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func automationStatus(bundleID: String) -> PermissionStatus {
        // Asking about an app that is not running returns procNotFound, so remember the last real answer.
        guard AppleScriptRunner.isRunning(bundleID: bundleID) else { return lastKnown[bundleID] ?? .notDetermined }
        let status = determine(bundleID: bundleID, ask: false)
        let result = map(status) ?? lastKnown[bundleID] ?? .notDetermined
        lastKnown[bundleID] = result
        return result
    }

    static func requestAutomation(bundleID: String) async {
        if !AppleScriptRunner.isRunning(bundleID: bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            for _ in 0..<20 where !AppleScriptRunner.isRunning(bundleID: bundleID) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        let status = await Task.detached { determine(bundleID: bundleID, ask: true) }.value
        if let mapped = map(status) { lastKnown[bundleID] = mapped }
    }

    private nonisolated static func determine(bundleID: String, ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return OSStatus(procNotFound) }
        return AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
    }

    private static func map(_ status: OSStatus) -> PermissionStatus? {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notDetermined
        default: nil
        }
    }
}
