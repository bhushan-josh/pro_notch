import NotchCore
import SwiftUI

@MainActor
public final class PrivacyFeature: NotchFeature {
    private let controller = PrivacyController()

    public init() {}

    public func start() {
        let controller = controller
        NotchRegistry.shared.register(settingsPane: SettingsPane(id: "privacy", title: "Camera & Microphone", symbol: "video.fill", color: .green, category: .notifications, order: 55) {
            PrivacySettingsView(controller: controller)
        })
        controller.start()
    }

    public func stop() {
        controller.stop()
    }
}
