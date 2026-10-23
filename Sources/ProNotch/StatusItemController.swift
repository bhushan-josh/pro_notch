import AppKit
import NotchCore

@MainActor
final class StatusItemController: NSObject {
    var onSettings: (() -> Void)?
    var onResetOnboarding: (() -> Void)?

    private var item: NSStatusItem?
    private var observer: AnyObject?

    func install() {
        apply()
        observer = Defaults.observe([CoreSettings.hideMenuBarIcon.name]) { [weak self] in self?.apply() }
    }

    private func apply() {
        if Defaults[CoreSettings.hideMenuBarIcon] {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.portrait.tophalf.filled", accessibilityDescription: "Pro Notch")
            ?? NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Pro Notch")
        item.menu = makeMenu()
        self.item = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pro Notch", action: #selector(openNotch), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Reset Onboarding", action: #selector(resetOnboarding), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reset Permissions…", action: #selector(resetPermissions), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pro Notch", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func openNotch() { NotchManager.shared.activeModel?.open() }
    @objc private func settings() { onSettings?() }
    @objc private func resetOnboarding() { onResetOnboarding?() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// Clears this app's TCC grants so macOS asks again; useful after rebuilding with a new ad-hoc signature.
    @objc private func resetPermissions() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleID]
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onResetOnboarding?() } }
        }
        try? process.run()
    }
}
