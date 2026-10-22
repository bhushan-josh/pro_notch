import AppKit
import NotchCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(pane: String?) {
        if let pane { selection.paneID = pane }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Dynamic Notch Settings"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 680, height: 460)
            window.contentView = NSHostingView(rootView: SettingsRootView().environment(selection))
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        observeClose()
    }

    private var closeObserver: NSObjectProtocol?

    private func observeClose() {
        guard closeObserver == nil, let window else { return }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var paneID: String? = "general"
}

struct SettingsRootView: View {
    @Environment(SettingsSelection.self) private var selection
    private let registry = NotchRegistry.shared

    var body: some View {
        @Bindable var selection = selection
        NavigationSplitView {
            List(selection: $selection.paneID) {
                ForEach(registry.settingsPanes) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        SettingsIcon(symbol: pane.symbol, color: pane.color)
                    }
                    .tag(pane.id as String?)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            if let pane = registry.settingsPanes.first(where: { $0.id == selection.paneID }) ?? registry.settingsPanes.first {
                pane.content()
                    .navigationTitle(pane.title)
                    .id(pane.id)
            }
        }
    }
}
