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
    private var openedByDrag = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var isFileDragActive = false
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
            guard let self else { return }
            if open { panel.ignoresMouseEvents = false } else { openedByDrag = false }
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
        updateFullscreenState()
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

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullscreenState() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullscreenState() }
        })

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
        if isFileDragActive { rect = rect.insetBy(dx: -40, dy: -30) }
        return rect
    }

    private func handleMouse(_ type: NSEvent.EventType) {
        let location = NSEvent.mouseLocation

        switch type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if !model.isOpen, interactiveRect.contains(location) { model.isPressed = true }
        case .leftMouseDragged:
            if !isFileDragActive, NotchRegistry.shared.dropHandler != nil,
               NSPasteboard(name: .drag).changeCount != dragChangeCount {
                isFileDragActive = true
            }
        case .leftMouseUp:
            model.isPressed = false
            if isFileDragActive {
                isFileDragActive = false
                model.isDropTargeted = false
            }
        default:
            break
        }

        if model.isResizing {
            panel.ignoresMouseEvents = false
            return
        }
        let inside = interactiveRect.contains(location)
        panel.ignoresMouseEvents = !inside

        if isFileDragActive {
            model.isDropTargeted = inside
            if inside, !model.isOpen {
                openedByDrag = true
                model.open(page: NotchRegistry.shared.dropPageID)
            }
        }

        if inside, !model.isHovering {
            model.isHovering = true
            closeTask?.cancel()
            if Defaults[CoreSettings.expandOnHover], !model.isOpen, !model.isSuppressed {
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
            guard model.isOpen, !isFileDragActive else { return }
            let delay = openedByDrag ? 400 : 120
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self, !self.model.isHovering else { return }
                self.model.close()
            }
        }
    }

    /// Two-finger swipes: down opens, up closes or dismisses, sideways skips media or cycles activities.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
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

    private func updateFullscreenState() {
        let fullscreen = SpaceInspector.fullscreenDisplayUUIDs()
        if SystemStatus.shared.fullscreenDisplays != fullscreen {
            SystemStatus.shared.fullscreenDisplays = fullscreen
        }
        let hide = Defaults[CoreSettings.hideInFullscreen] && fullscreen.contains(model.geometry.displayUUID)
        if hide != model.isHiddenForFullscreen {
            withAnimation(.easeInOut(duration: 0.2)) { model.isHiddenForFullscreen = hide }
            if hide { model.close() }
        }
    }
}
