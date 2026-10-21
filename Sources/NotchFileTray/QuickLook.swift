import AppKit
import NotchCore
import QuickLookUI

/// Feeds tray files to the shared Quick Look panel. The notch panel is not in the app's responder chain,
/// so the data source is assigned directly instead of through `acceptsPreviewPanelControl`.
@MainActor
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    func preview(_ urls: [URL], startingAt index: Int = 0) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = min(max(0, index), urls.count - 1)
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated {
            guard urls.indices.contains(index) else { return nil }
            return urls[index] as NSURL
        }
    }
}

@MainActor
enum FileActions {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        NotchManager.shared.closeAll()
    }

    static func showInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        NotchManager.shared.closeAll()
    }

    static func copy(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }

    static var canAirDrop: Bool { NSSharingService(named: .sendViaAirDrop) != nil }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        let items = urls.map { $0 as NSURL }
        guard service.canPerform(withItems: items) else { return }
        NSApp.activate()
        service.perform(withItems: items)
    }

    static func share(_ urls: [URL], from view: NSView?) {
        guard !urls.isEmpty, let view, view.window != nil else { return }
        let picker = NSSharingServicePicker(items: urls.map { $0 as NSURL })
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}
