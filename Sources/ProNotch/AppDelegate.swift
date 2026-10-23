import AppKit
import NotchCalendar
import NotchClipboard
import NotchCore
import NotchDownloads
import NotchHUD
import NotchKeepAwake
import NotchLock
import NotchMedia
import NotchPrivacy
import NotchStats
import NotchSystem
import NotchTimers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let features: [NotchFeature] = [
        MediaFeature(),
        HUDFeature(),
        SystemFeature(),
        CalendarFeature(),
        LockFeature(),
        DownloadsFeature(),
        TimersFeature(),
        PrivacyFeature(),
        ClipboardFeature(),
        StatsFeature(),
        KeepAwakeFeature(),
    ]
    private let statusItem = StatusItemController()
    private let settingsWindow = SettingsWindowController()
    private var onboarding: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchRegistry.shared.openSettings = { [weak self] pane in
            NotchManager.shared.closeAll()
            self?.settingsWindow.show(pane: pane)
        }
        GeneralSettings.registerPanes()
        features.forEach { $0.start() }
        NotchManager.shared.start()

        statusItem.onSettings = { [weak self] in self?.settingsWindow.show(pane: nil) }
        statusItem.onResetOnboarding = { [weak self] in self?.showOnboarding() }
        statusItem.install()

        if !Defaults[CoreSettings.onboardingCompleted] { showOnboarding() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        features.forEach { $0.stop() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show(pane: nil)
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pronotch" {
            switch url.host {
            case "settings": settingsWindow.show(pane: url.pathComponents.dropFirst().first)
            case "open": NotchManager.shared.activeModel?.open()
            case "close": NotchManager.shared.closeAll()
            default: break
            }
        }
    }

    private func showOnboarding() {
        let controller = OnboardingWindowController { [weak self] in
            Defaults[CoreSettings.onboardingCompleted] = true
            self?.onboarding = nil
        }
        onboarding = controller
        controller.show()
    }
}
