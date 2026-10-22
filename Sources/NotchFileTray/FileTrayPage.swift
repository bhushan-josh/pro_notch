import AppKit
import NotchCore
import SwiftUI

struct FileTrayPage: View {
    let store: FileTrayStore

    @Environment(NotchModel.self) private var model
    @AppStorage(FileTraySettings.showAirDropTarget) private var showAirDropTarget
    @AppStorage(FileTraySettings.tileSize) private var tileSize
    @State private var shareAnchor = ViewAnchor.Box()

    var body: some View {
        HStack(spacing: 12) {
            if store.items.isEmpty {
                EmptyTrayView(isTargeted: model.isDropTargeted)
            } else {
                VStack(spacing: 6) {
                    toolbar
                    tiles
                }
            }
            if showAirDropTarget, FileActions.canAirDrop {
                AirDropTarget()
                    .frame(width: 92)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.pruneMissing() }
    }

    private var toolbar: some View {
        let count = store.items.count
        return HStack(spacing: 8) {
            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            ToolbarChip(symbol: "hand.draw.fill", title: "Drag All")
                .overlay(MultiFileDragSource(urls: store.urls))
                .help("Drag every file in the tray at once")
            if FileActions.canAirDrop {
                Button { FileActions.airDrop(store.urls) } label: {
                    ToolbarChip(symbol: "dot.radiowaves.up.forward", title: "AirDrop All")
                }
                .buttonStyle(.plain)
            }
            Button { FileActions.share(store.urls, from: shareAnchor.view) } label: {
                ToolbarChip(symbol: "square.and.arrow.up", title: nil)
            }
            .buttonStyle(.plain)
            .background(ViewAnchor(box: shareAnchor))
            .help("Share all")
            Button { store.removeAll() } label: {
                ToolbarChip(symbol: "trash", title: "Clear")
            }
            .buttonStyle(.plain)
        }
        .frame(height: 22)
    }

    /// One scrolling row while the tray is short; a wrapping grid once it is tall enough for two rows.
    private var tiles: some View {
        GeometryReader { proxy in
            let tile = tileSize.tileSize
            if proxy.size.height >= tile.height * 2 + 4 {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tile.width, maximum: tile.width + 12), spacing: 4)], spacing: 4) {
                        tileViews
                    }
                    .padding(.top, 2)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) { tileViews }
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(model.isDropTargeted ? 0.35 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .animation(.easeOut(duration: 0.15), value: model.isDropTargeted)
    }

    private var tileViews: some View {
        ForEach(store.items) { item in
            FileTile(item: item, store: store)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

private struct ToolbarChip: View {
    let symbol: String
    let title: String?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            if let title {
                Text(title).font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.7))
        .padding(.horizontal, title == nil ? 7 : 9)
        .frame(height: 22)
        .background(.white.opacity(isHovering ? 0.18 : 0.1), in: Capsule())
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
    }
}

private struct EmptyTrayView: View {
    let isTargeted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(.white.opacity(isTargeted ? 0.6 : 0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isTargeted ? 0.08 : 0))
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray")
                        .font(.system(size: 26, weight: .medium))
                        .symbolEffect(.bounce, value: isTargeted)
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(isTargeted ? 0.95 : 0.5))
            }
            .scaleEffect(isTargeted ? 1.02 : 1)
            .animation(.notchSnappy, value: isTargeted)
    }
}

private struct AirDropTarget: View {
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(isTargeted ? Color.blue.opacity(0.35) : .white.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isTargeted ? Color.blue.opacity(0.9) : .white.opacity(0.12), lineWidth: 1.5)
            }
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(isTargeted ? .white : .blue)
                        .symbolEffect(.bounce, value: isTargeted)
                    Text("AirDrop")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.7))
                }
            }
            .scaleEffect(isTargeted ? 1.04 : 1)
            .animation(.notchSnappy, value: isTargeted)
            .onDrop(of: DropLoader.acceptedTypes, isTargeted: $isTargeted) { providers in
                Task {
                    let payloads = await DropLoader.load(providers)
                    let urls = payloads.compactMap(TrayFileWriter.temporaryFile)
                    FileActions.airDrop(urls)
                }
                return true
            }
            .help("Drop files to send them with AirDrop")
    }
}
