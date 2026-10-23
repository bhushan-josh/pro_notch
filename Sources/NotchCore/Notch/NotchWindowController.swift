import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
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
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that ignores the notch safe area and accepts clicks without activating the app.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    let screen: NSScreen
    let model: NotchModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var settingsObserver: AnyObject?
    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var scrollAccumulator = CGSize.zero
    private var scrollConsumed = false

    init(screen: NSScreen) {
        self.screen = screen
        model = NotchModel(geometry: .make(for: screen))
        panel = NotchPanel(contentRect: .zero)

        let root = NotchRootView().environment(model)
        let hosting = NotchHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        layoutPanel()
        applySettings()
        panel.orderFrontRegardless()
        applyLockScreenPresence()
        installMonitors()

        model.onOpenChange = { [weak self] open in
            if open { self?.setIgnoresMouseEvents(false) }
        }
    }

    func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        OverlaySpace.shared.remove(panel)
        panel.orderOut(nil)
    }

    func refreshGeometry() {
        let geometry = NotchGeometry.make(for: screen)
        if geometry != model.geometry { model.geometry = geometry }
        layoutPanel()
    }

    private func layoutPanel() {
        let size = NotchLayout.windowSize(geometry: model.geometry)
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    private func applySettings() {
        panel.sharingType = Defaults[CoreSettings.hideFromScreenCapture] ? .none : .readOnly
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        behavior.insert(Defaults[CoreSettings.hideInMissionControl] ? .transient : .stationary)
        panel.collectionBehavior = behavior
        applyFullscreen(NotchManager.shared.fullscreenDisplays)
    }

    private func applyLockScreenPresence() {
        if Defaults[CoreSettings.showOnLockScreen] {
            OverlaySpace.shared.add(panel)
        } else {
            OverlaySpace.shared.remove(panel)
        }
    }

    // MARK: - Event handling

    private func installMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse(event.type) }
            return event
        }) { monitors.append(local) }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self else { return event }
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self.handleScroll(event) }
            return consumed ? nil : event
        }) { monitors.append(scroll) }


        settingsObserver = Defaults.observe([
            CoreSettings.hideFromScreenCapture.name, CoreSettings.hideInMissionControl.name,
            CoreSettings.hideInFullscreen.name, CoreSettings.showOnLockScreen.name,
            CoreSettings.notchWidthOffset.name, CoreSettings.notchHeightOffset.name,
            CoreSettings.forceSimulatedNotch.name,
        ]) { [weak self] in
            self?.applySettings()
            self?.applyLockScreenPresence()
            self?.refreshGeometry()
        }
    }

    /// Screen-space rect the pointer must be in to count as hovering the notch.
    private var interactiveRect: NSRect {
        let windowFrame = panel.frame
        let shape = model.shapeFrame
        var rect = NSRect(
            x: windowFrame.minX + shape.minX,
            y: windowFrame.maxY - shape.maxY,
            width: shape.width,
            height: shape.height
        )
        let notch = model.geometry.notchSize
        let notchRect = NSRect(
            x: screen.frame.midX - notch.width / 2,
            y: screen.frame.maxY - notch.height,
            width: notch.width,
            height: notch.height
        )
        rect = rect.isEmpty ? notchRect : rect.union(notchRect)
        // A pointer pinned to the top edge reports y == maxY, which NSRect.contains treats as outside.
        rect.size.height += 2
        return rect
    }

    /// Runs for every mouse event on screen, so it avoids writes (and WindowServer calls) when nothing changes.
    private func handleMouse(_ type: NSEvent.EventType) {
        if type == .leftMouseUp {
            if model.isPressed { model.isPressed = false }
            // The resize gesture's own end handler is skipped if its view disappears mid-drag.
            if model.isResizing { model.isResizing = false }
        }
        if model.isResizing {
            setIgnoresMouseEvents(false)
            return
        }
        // Hidden for a fullscreen app: invisible and untouchable, so clicks reach the app's own top strip.
        if model.isSuppressed {
            setIgnoresMouseEvents(true)
            if model.isHovering { model.isHovering = false }
            hoverTask?.cancel()
            return
        }

        let inside = interactiveRect.contains(NSEvent.mouseLocation)
        setIgnoresMouseEvents(!inside)

        if type == .leftMouseDown {
            if inside {
                if !model.isOpen { model.isPressed = true }
            } else if model.isOpen {
                model.close()
            }
        }

        if inside, !model.isHovering {
            model.isHovering = true
            closeTask?.cancel()
            if Defaults[CoreSettings.expandOnHover], !model.isOpen {
                let delay = Defaults[CoreSettings.hoverDuration]
                hoverTask?.cancel()
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled, let self, self.model.isHovering else { return }
                    self.model.open()
                }
            }
        } else if !inside, model.isHovering {
            model.isHovering = false
            hoverTask?.cancel()
            guard model.isOpen else { return }
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, !self.model.isHovering else { return }
                self.model.close()
            }
        }
    }

    private func setIgnoresMouseEvents(_ ignores: Bool) {
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    /// Two-finger swipes: down opens, up closes or dismisses, sideways skips media or cycles activities.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard event.window === panel, !model.isSuppressed else { return false }
        // Momentum after a finished swipe would otherwise cross the threshold again and act a second time.
        if !event.momentumPhase.isEmpty { return !model.isOpen }
        if event.phase == .began || event.phase == .mayBegin {
            scrollAccumulator = .zero
            scrollConsumed = false
        }
        guard event.hasPreciseScrollingDeltas else { return false }
        if scrollConsumed {
            if event.phase == .ended || event.phase == .cancelled { scrollConsumed = false }
            return true
        }

        var natural = event.isDirectionInvertedFromDevice
        if !Defaults[CoreSettings.naturalMovement] { natural.toggle() }
        let sign: CGFloat = natural ? 1 : -1
        scrollAccumulator.width += event.scrollingDeltaX * sign
        scrollAccumulator.height += event.scrollingDeltaY * sign

        let threshold: CGFloat = 28
        let dx = scrollAccumulator.width, dy = scrollAccumulator.height
        guard max(abs(dx), abs(dy)) > threshold else { return model.isOpen ? false : true }

        let direction: SwipeDirection = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
        scrollConsumed = true
        scrollAccumulator = .zero
        switch direction {
        case .down:
            if Defaults[CoreSettings.swipeToToggle], !model.isOpen { model.open() }
        case .up:
            if model.isOpen {
                if Defaults[CoreSettings.swipeToToggle] { model.close() }
            } else if Defaults[CoreSettings.swipeToDismiss] {
                ActivityCenter.shared.dismissCurrent()
            }
        case .left, .right:
            if model.isOpen { scrollConsumed = false; return false }
            if Defaults[CoreSettings.swipeToSkip], NotchRegistry.shared.handleSwipe(direction) {
                Haptics.perform()
            } else if Defaults[CoreSettings.swipeToCycleActivity] {
                ActivityCenter.shared.cycleIdle(by: direction == .right ? 1 : -1)
                Haptics.perform()
            }
        }
        return true
    }

    /// Called by NotchManager, which queries the window server once per space change for all displays.
    func applyFullscreen(_ fullscreen: Set<String>) {
        let hide = Defaults[CoreSettings.hideInFullscreen] && fullscreen.contains(model.geometry.displayUUID)
        if hide != model.isHiddenForFullscreen {
            withAnimation(.easeInOut(duration: 0.2)) { model.isHiddenForFullscreen = hide }
            if hide { model.close() }
        }
    }
}
