import AppKit
import SwiftUI

/// Owns one notch window per target display and rebuilds them when displays or settings change.
@MainActor
public final class NotchManager {
    public static let shared = NotchManager()

    private var controllers: [String: NotchWindowController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var spaceObservers: [NSObjectProtocol] = []
    /// Display UUIDs currently showing a fullscreen app.
    private(set) var fullscreenDisplays: Set<String> = []
    private var settingsObserver: AnyObject?

    private init() {}

    public func start() {
        NotchRegistry.shared.register(page: NotchPage(id: NotchModel.homePageID, title: "Home", symbol: "house.fill", order: 0) {
            HomePageView()
        })
        fullscreenDisplays = SpaceInspector.fullscreenDisplayUUIDs()
        rebuild()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            spaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullscreen() }
            })
        }
        screenObserver = NotchCenterObserver.screenParameters { [weak self] in self?.rebuild() }
        settingsObserver = Defaults.observe([CoreSettings.displayTarget.name, CoreSettings.specificDisplayUUID.name]) { [weak self] in
            self?.rebuild()
        }
    }

    /// The model on the screen under the pointer, falling back to the first window.
    public var activeModel: NotchModel? {
        let mouse = NSEvent.mouseLocation
        return controllers.values.first { $0.screen.frame.contains(mouse) }?.model ?? controllers.values.first?.model
    }

    public var models: [NotchModel] { controllers.values.map(\.model) }

    private func updateFullscreen() {
        fullscreenDisplays = SpaceInspector.fullscreenDisplayUUIDs()
        controllers.values.forEach { $0.applyFullscreen(fullscreenDisplays) }
    }

    public func closeAll() { models.forEach { $0.close() } }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch Defaults[CoreSettings.displayTarget] {
        case .all:
            return screens
        case .main:
            return NSScreen.main.map { [$0] } ?? []
        case .builtIn:
            return [screens.first(where: \.isBuiltIn) ?? NSScreen.main].compactMap { $0 }
        case .specific:
            let uuid = Defaults[CoreSettings.specificDisplayUUID]
            return [screens.first { $0.displayUUID == uuid } ?? NSScreen.main].compactMap { $0 }
        }
    }

    private func rebuild() {
        let screens = targetScreens()
        let wanted = Set(screens.map(\.displayUUID))
        for (uuid, controller) in controllers where !wanted.contains(uuid) {
            controller.tearDown()
            controllers.removeValue(forKey: uuid)
        }
        for screen in screens {
            let uuid = screen.displayUUID
            if let existing = controllers[uuid] {
                if existing.screen.frame != screen.frame {
                    existing.tearDown()
                    controllers[uuid] = NotchWindowController(screen: screen)
                } else {
                    existing.refreshGeometry()
                }
            } else {
                controllers[uuid] = NotchWindowController(screen: screen)
            }
        }
    }
}

enum NotchCenterObserver {
    static func screenParameters(_ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}
