import AppKit
import SwiftUI
import Observation
import NotchCore

private final class LockScreenPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    // Never take key focus: on the lock screen that would steal typing from the password field.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class LockScreenHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
@Observable
final class LockScreenWindowModel {
    var isPresented = false
}

/// The transparent panel below the lock screen clock that hosts the registered lock screen widgets.
@MainActor
final class LockScreenWindowController {
    private static let panelSize = CGSize(width: LockWidgetMetrics.width + 48, height: 620)

    private let model = LockScreenWindowModel()
    private let panel = LockScreenPanel()
    private var hideTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var settingsObserver: AnyObject?
    private var isPreviewing = false
    // Mirrors model.isPresented without registering an observation dependency in callers' tracking loops.
    private var isShown = false

    init() {
        let hosting = LockScreenHostingView(rootView: LockScreenWidgetStack(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func start() {
        layout()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        settingsObserver = Defaults.observe([
            LockSettings.widgetOffset.name, LockSettings.widgetsEnabled.name, LockSettings.showOnScreenSaver.name,
        ]) { [weak self] in
            self?.layout()
            self?.update()
        }
        update()
    }

    func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        settingsObserver = nil
        previewTask?.cancel()
        hideTask?.cancel()
        isShown = false
        model.isPresented = false
        OverlaySpace.shared.remove(panel)
        panel.orderOut(nil)
    }

    var shouldShow: Bool {
        // Read observable state before any Defaults check so ObservationLoop always has something to track.
        let status = SystemStatus.shared
        let isLocked = status.isScreenLocked
        let isScreenSaverActive = status.isScreenSaverActive
        guard Defaults[LockSettings.widgetsEnabled] else { return false }
        if isScreenSaverActive { return Defaults[LockSettings.showOnScreenSaver] }
        return isLocked
    }

    func update() {
        if shouldShow || isPreviewing { show() } else { hide() }
    }

    /// Shows the widgets on the desktop for a few seconds so the offset and style can be tuned.
    func preview() {
        isPreviewing = true
        update()
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.isPreviewing = false
            self.update()
        }
    }

    private func show() {
        hideTask?.cancel()
        guard !isShown || !panel.isVisible else { return }
        isShown = true
        layout()
        panel.orderFrontRegardless()
        OverlaySpace.shared.add(panel)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { model.isPresented = true }
    }

    private func hide() {
        guard isShown || panel.isVisible else { return }
        isShown = false
        withAnimation(.easeOut(duration: 0.25)) { model.isPresented = false }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            OverlaySpace.shared.remove(self.panel)
            self.panel.orderOut(nil)
        }
    }

    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = Self.panelSize
        // The lock screen clock occupies roughly the top quarter of the display.
        let top = frame.maxY - frame.height * 0.27 - Defaults[LockSettings.widgetOffset]
        let y = min(max(top - size.height, frame.minY), frame.maxY - size.height)
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
    }
}

struct LockScreenWidgetStack: View {
    let model: LockScreenWindowModel
    @AppStorage(LockSettings.widgetStyle) private var style
    @AppStorage(LockSettings.showMediaWidget) private var showMedia
    @AppStorage(LockSettings.showWeatherWidget) private var showWeather
    private let registry = NotchRegistry.shared
    private let status = SystemStatus.shared

    private var widgets: [LockScreenWidget] {
        registry.lockScreenWidgets.filter { widget in
            switch widget.id {
            case "media": showMedia && status.isMediaPlaying
            case WeatherWidget.id: showWeather && status.weather != nil
            default: true
            }
        }
    }

    var body: some View {
        VStack(spacing: LockWidgetMetrics.spacing) {
            ForEach(widgets) { widget in
                widget.content()
                    .padding(LockWidgetMetrics.padding)
                    .frame(width: LockWidgetMetrics.width)
                    .lockWidgetBackground(style)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .opacity(model.isPresented ? 1 : 0)
        .scaleEffect(model.isPresented ? 1 : 0.94, anchor: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: widgets.map(\.id))
        .ignoresSafeArea()
    }
}
