import NotchCore
import SwiftUI

@MainActor
public final class ClipboardFeature: NotchFeature {
    public static let pageID = "clipboard"
    static let copiedActivityID = "clipboard.copied"

    private let store = ClipboardStore()
    private var settingsObserver: AnyObject?

    public init() {}

    public func start() {
        let store = store
        NotchRegistry.shared.register(settingsPane: SettingsPane(id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard", color: .blue, category: .general, order: 20) {
            ClipboardSettingsView(store: store)
        })
        store.onCapture = { [weak self] item in self?.showCopied(item) }

        apply()
        settingsObserver = Defaults.observe([
            ClipboardSettings.enabled.name,
            ClipboardSettings.maxItems.name,
            ClipboardSettings.persist.name,
        ]) { [weak self] in
            self?.apply()
        }
    }

    public func stop() {
        settingsObserver = nil
        store.stop()
        updatePage(visible: false)
        ActivityCenter.shared.dismiss(id: Self.copiedActivityID)
    }

    private func apply() {
        store.persistenceChanged()
        store.trim()
        if Defaults[ClipboardSettings.enabled] {
            store.start()
            updatePage(visible: true)
        } else {
            store.stop()
            updatePage(visible: false)
        }
    }

    private func updatePage(visible: Bool) {
        let registry = NotchRegistry.shared
        if visible {
            guard !registry.pages.contains(where: { $0.id == Self.pageID }) else { return }
            let store = store
            registry.register(page: NotchPage(
                id: Self.pageID,
                title: "Clipboard",
                symbol: "doc.on.clipboard",
                order: 30,
                resize: PageResize(minSize: CGSize(width: 375, height: 180), maxSize: CGSize(width: 640, height: 480))
            ) {
                ClipboardPage(store: store)
            })
        } else {
            for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
                model.selectedPageID = NotchModel.homePageID
            }
            registry.unregister(pageID: Self.pageID)
        }
    }

    private func showCopied(_ item: ClipboardItem) {
        guard Defaults[ClipboardSettings.showCopiedActivity] else { return }
        let id = item.id
        ActivityCenter.shared.present(LiveActivity(
            id: Self.copiedActivityID,
            category: .other,
            priority: .low,
            duration: 1.2,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { ClipboardCopiedLeading() },
            trailing: { ClipboardCopiedTrailing(id: id) },
            onTap: { NotchManager.shared.activeModel?.open(page: ClipboardFeature.pageID) }
        ))
    }
}
