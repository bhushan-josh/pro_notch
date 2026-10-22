import AppKit
import NotchCore
import SwiftUI

struct FileTile: View {
    let item: FileTrayItem
    let store: FileTrayStore

    @State private var isHovering = false
    @State private var anchor = ViewAnchor.Box()
    @AppStorage(FileTraySettings.tileSize) private var size

    var body: some View {
        VStack(spacing: 5) {
            thumbnail
                .frame(width: size.thumbnail, height: size.thumbnail)
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: size.labelWidth, height: 26, alignment: .top)
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .background(isHovering ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(ViewAnchor(box: anchor))
        .overlay(alignment: .topLeading) {
            if isHovering {
                removeButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture { FileActions.open(item.url) }
        .onDrag {
            let provider = NSItemProvider(object: item.url as NSURL)
            provider.suggestedName = item.url.lastPathComponent
            return provider
        } preview: {
            thumbnail.frame(width: size.thumbnail, height: size.thumbnail)
        }
        .contextMenu { menu }
        .help([item.name, item.formattedSize].compactMap { $0 }.joined(separator: " - "))
        .task(id: item.id) { await store.loadThumbnail(for: item) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = store.thumbnails[item.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(for: item.contentType))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(0.6)
        }
    }

    private var removeButton: some View {
        Button {
            store.remove(item)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color(white: 0.28), in: Circle())
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: -2, y: -2)
        .help("Remove from Tray")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { FileActions.open(item.url) }
        Button("Show in Finder") { FileActions.showInFinder([item.url]) }
        Button("Quick Look") {
            let urls = store.urls
            QuickLookController.shared.preview(urls, startingAt: urls.firstIndex(of: item.url) ?? 0)
        }
        Divider()
        if FileActions.canAirDrop {
            Button("AirDrop") { FileActions.airDrop([item.url]) }
        }
        Button("Share…") { FileActions.share([item.url], from: anchor.view) }
        Button("Copy") { FileActions.copy([item.url]) }
        Divider()
        Button("Remove", role: .destructive) { store.remove(item) }
    }
}

/// Exposes the backing NSView of a SwiftUI view so AppKit popovers (the share picker) can anchor to it.
struct ViewAnchor: NSViewRepresentable {
    final class Box {
        weak var view: NSView?
    }

    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// An AppKit drag source that drags several files in one session, which SwiftUI's `onDrag` cannot do.
struct MultiFileDragSource: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.urls = urls
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.urls = urls
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        private var mouseDown: NSEvent?

        /// Keeps the source alive if the notch closes and tears the view down mid-drag.
        private static var activeSource: DragSourceView?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDown = event
        }

        override func mouseUp(with event: NSEvent) {
            mouseDown = nil
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDown, !urls.isEmpty else { return }
            mouseDown = nil
            let origin = convert(down.locationInWindow, from: nil)
            let iconSize: CGFloat = 40
            let items = urls.prefix(64).enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: iconSize, height: iconSize)
                let shift = CGFloat(min(index, 4)) * 4
                item.setDraggingFrame(
                    NSRect(x: origin.x - iconSize / 2 + shift, y: origin.y - iconSize / 2 - shift, width: iconSize, height: iconSize),
                    contents: icon
                )
                return item
            }
            let session = beginDraggingSession(with: Array(items), event: down, source: self)
            session.draggingFormation = .pile
            session.animatesToStartingPositionsOnCancelOrFail = true
            Self.activeSource = self
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            Self.activeSource = nil
        }
    }
}
