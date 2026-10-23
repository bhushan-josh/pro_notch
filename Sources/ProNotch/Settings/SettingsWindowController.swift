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
            window.title = "Pro Notch Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            // An empty unified toolbar gives the taller titlebar the pane header lines up with.
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
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

    /// Dropping the window on close also stops the timers its panes run (the Permissions pane polls every 2s).
    private func observeClose() {
        guard closeObserver == nil, let window else { return }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let observer = self.closeObserver { NotificationCenter.default.removeObserver(observer) }
                self.closeObserver = nil
                self.window?.contentView = nil
                self.window = nil
                _ = NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var paneID: String? = "general"
}

/// Height of the unified titlebar the traffic lights sit in.
private let titlebarHeight: CGFloat = 52

struct SettingsRootView: View {
    @Environment(SettingsSelection.self) private var selection
    private let registry = NotchRegistry.shared

    /// Panes in sidebar order, so arrow keys step through them as listed.
    private var panes: [SettingsPane] {
        SettingsCategory.allCases.flatMap { category in registry.settingsPanes.filter { $0.category == category } }
    }

    private var current: SettingsPane? {
        panes.first { $0.id == selection.paneID } ?? panes.first
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(panes: panes, selectedID: current?.id) { selection.paneID = $0 }
                .frame(width: 230)
                .background(SidebarMaterial())
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { step(-1) }
                .onKeyPress(.downArrow) { step(1) }
            Divider()
            if let current {
                SettingsDetail(pane: current)
                    .id(current.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let index = panes.firstIndex(where: { $0.id == current?.id }) else { return .ignored }
        let next = index + offset
        guard panes.indices.contains(next) else { return .handled }
        selection.paneID = panes[next].id
        return .handled
    }
}

private struct SettingsSidebar: View {
    let panes: [SettingsPane]
    let selectedID: String?
    let select: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsCategory.allCases) { category in
                    let items = panes.filter { $0.category == category }
                    if !items.isEmpty {
                        if let title = category.title {
                            Text(title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 18)
                                .padding(.bottom, 4)
                        }
                        ForEach(items) { pane in
                            SidebarRow(pane: pane, isSelected: pane.id == selectedID) { select(pane.id) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .clipped()
        .padding(.top, titlebarHeight)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Always reachable, even with the menu bar icon hidden.
            VStack(spacing: 0) {
                Divider()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Pro Notch", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("q")
                .padding(12)
            }
            .background(SidebarMaterial())
        }
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: pane.symbol, color: pane.color)
                Text(pane.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.primary.opacity(0.09) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDetail: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: pane.symbol, color: pane.color)
                Text(pane.title)
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 20)
            .frame(height: titlebarHeight)
            pane.content()
                .clipped()
        }
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
