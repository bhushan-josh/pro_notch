import NotchCore
import Observation
import SwiftUI

@MainActor
public final class FileTrayFeature: NotchFeature {
    public static let pageID = "fileTray"

    public let store = FileTrayStore()
    private let idleProvider: FileTrayIdleProvider
    private var settingsObserver: AnyObject?
    private var isRegistered = false

    public init() {
        idleProvider = FileTrayIdleProvider(store: store)
    }

    public func start() {
        let registry = NotchRegistry.shared
        let store = store
        store.restore()
        store.onAdd = { [weak self] count in self?.didAdd(count) }

        registry.register(settingsPane: SettingsPane(id: "fileTray", title: "File Tray", symbol: "tray.fill", color: .purple, order: 80) {
            FileTraySettingsView(store: store)
        })
        registry.register(idleProvider: idleProvider)

        applySettings()
        settingsObserver = Defaults.observe([
            FileTraySettings.enabled.name, FileTraySettings.persist.name,
            FileTraySettings.maxItems.name, FileTraySettings.showIdleIndicator.name,
        ]) { [weak self] in
            self?.applySettings()
        }
    }

    public func stop() {
        settingsObserver = nil
        unregister()
        store.save()
    }

    private func applySettings() {
        let enabled = Defaults[FileTraySettings.enabled]
        if enabled { register() } else { unregister() }
        idleProvider.isEnabled = enabled && Defaults[FileTraySettings.showIdleIndicator]
        store.trimToLimit()
        store.save()
    }

    private func register() {
        guard !isRegistered else { return }
        isRegistered = true
        let registry = NotchRegistry.shared
        let store = store
        let resize = PageResize(minSize: CGSize(width: 380, height: 150), maxSize: NotchLayout.maxResizableSize)
        registry.register(page: NotchPage(id: Self.pageID, title: "File Tray", symbol: "tray.fill", order: 10, resize: resize) {
            FileTrayPage(store: store)
        })
        registry.dropHandler = { providers in
            store.add(providers: providers)
            return true
        }
        registry.dropPageID = Self.pageID
    }

    private func unregister() {
        guard isRegistered else { return }
        isRegistered = false
        let registry = NotchRegistry.shared
        registry.unregister(pageID: Self.pageID)
        registry.dropHandler = nil
        if registry.dropPageID == Self.pageID { registry.dropPageID = nil }
        ActivityCenter.shared.dismiss(id: "fileTray.added")
        for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
            model.selectedPageID = NotchModel.homePageID
        }
    }

    private func didAdd(_ count: Int) {
        guard !NotchManager.shared.models.contains(where: \.isOpen) else { return }
        let total = store.items.count
        ActivityCenter.shared.present(LiveActivity(
            id: "fileTray.added",
            category: .fileTray,
            priority: .low,
            duration: Defaults[CoreSettings.activityDuration],
            leading: {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            },
            trailing: {
                Text("\(total)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            },
            onTap: { FileTrayFeature.openTray() }
        ))
    }

    static func openTray() {
        NotchManager.shared.activeModel?.open(page: pageID)
    }
}

@MainActor
@Observable
final class FileTrayIdleProvider: IdleActivityProvider {
    private let store: FileTrayStore
    var isEnabled = false

    init(store: FileTrayStore) {
        self.store = store
    }

    var idleActivity: LiveActivity? {
        guard isEnabled, !store.items.isEmpty else { return nil }
        let count = store.items.count
        return LiveActivity(
            id: "fileTray.idle",
            category: .fileTray,
            priority: .idle,
            leading: {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            },
            trailing: {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            },
            onTap: { FileTrayFeature.openTray() }
        )
    }

    var idleActivityUpdatedAt: Date { store.updatedAt }
}
