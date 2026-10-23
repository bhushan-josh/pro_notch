import AppKit
import NotchCore
import SwiftUI

// MARK: Closed notch

struct ClipboardCopiedLeading: View {
    var body: some View {
        Image(systemName: "doc.on.clipboard")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipboardCopiedTrailing: View {
    let id: UUID

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: id)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: Clipboard page

struct ClipboardPage: View {
    let store: ClipboardStore
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var copiedReset: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 6) {
            header
            let visible = filteredItems
            if visible.isEmpty {
                emptyState
            } else {
                // Relative times only need to move on by the minute.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(visible) { item in
                                ClipboardRow(item: item, store: store, now: context.date, isCopied: copiedID == item.id) {
                                    copy(item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredItems: [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.items }
        return store.items.filter { $0.matches(trimmed) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.white.opacity(0.08), in: Capsule())

            if store.items.contains(where: { !$0.isPinned }) {
                Button("Clear") { withAnimation(.notchSnappy) { store.clear(keepingPinned: true) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background(.white.opacity(0.1), in: Capsule())
                    .help("Clear history, keeping pinned items")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
            Text(query.isEmpty ? "Copied items appear here" : "No matches")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ item: ClipboardItem) {
        store.copy(item)
        Haptics.perform()
        withAnimation(.notchSnappy) { copiedID = item.id }
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.notchSnappy) { copiedID = nil }
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let now: Date
    let isCopied: Bool
    let onCopy: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 22, height: 22)
            Text(item.preview)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(item.kind == .file ? .middle : .tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Group {
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(Self.relative(item.date, now: now))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isHovering ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onCopy)
        .onDrag { store.itemProvider(for: item) }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button(item.isPinned ? "Unpin" : "Pin") { withAnimation(.notchSnappy) { store.togglePin(item) } }
            if let url = item.url {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            if item.kind == .file {
                Button("Open") { item.fileURLs.forEach { NSWorkspace.shared.open($0) } }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
            }
            Divider()
            Button("Delete") { withAnimation(.notchSnappy) { store.delete(item) } }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        switch item.kind {
        case .file: (item.filePaths ?? []).joined(separator: "\n")
        case .url: item.text ?? ""
        default: ""
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let thumbnail = store.thumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                SymbolTile(symbol: "photo")
            }
        case .file:
            Image(nsImage: store.fileIcon(for: item))
                .resizable()
                .interpolation(.high)
        case .url:
            SymbolTile(symbol: "link")
        case .richText:
            SymbolTile(symbol: "textformat")
        case .text:
            SymbolTile(symbol: "text.alignleft")
        }
    }

    static func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}

private struct SymbolTile: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: 22, height: 22)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
