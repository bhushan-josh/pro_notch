import AppKit
import NotchCore
import SwiftUI
import UniformTypeIdentifiers

/// A thin circular gauge; spins a short arc when the total size is unknown.
struct ProgressRing: View {
    var fraction: Double
    var indeterminate = false
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: lineWidth)
            if indeterminate {
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(angle))
                }
            } else {
                Circle()
                    .trim(from: 0, to: max(0.02, min(fraction, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: fraction)
            }
        }
    }
}

enum FileIcons {
    static func icon(for item: DownloadItem) -> NSImage {
        let url = item.fileURL
        if FileManager.default.fileExists(atPath: url.path), !DownloadMonitor.isPartial(url) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let ext = (item.displayName as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

enum ByteText {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func string(_ bytes: Int64) -> String { formatter.string(fromByteCount: max(bytes, 0)) }

    static func remaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds))) sec left" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min left" }
        return String(format: "%.1f hr left", seconds / 3600)
    }

    static func detail(for item: DownloadItem) -> String {
        switch item.state {
        case .finished:
            return item.totalBytes > 0 ? string(item.totalBytes) : "Downloaded"
        case .failed:
            return "Failed or cancelled"
        case .active:
            var parts: [String] = []
            parts.append(item.totalBytes > 0 ? "\(string(item.completedBytes)) of \(string(item.totalBytes))" : string(item.completedBytes))
            if let left = item.remainingTime { parts.append(remaining(left)) }
            return parts.joined(separator: " · ")
        }
    }
}

// MARK: Closed notch

struct DownloadLeadingWing: View {
    let monitor: DownloadMonitor

    var body: some View {
        let active = monitor.activeItems
        ZStack(alignment: .bottomTrailing) {
            if let first = active.first {
                Image(nsImage: FileIcons.icon(for: first))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            }
            if active.count > 1 {
                Text("\(active.count)")
                    .font(.system(size: 8, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.black)
                    .frame(minWidth: 11, minHeight: 11)
                    .background(.white, in: Capsule())
                    .offset(x: 4, y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DownloadTrailingWing: View {
    let monitor: DownloadMonitor

    var body: some View {
        let active = monitor.activeItems
        let known = active.filter { !$0.isIndeterminate }
        let total = known.reduce(Int64(0)) { $0 + $1.totalBytes }
        let done = known.reduce(Int64(0)) { $0 + $1.completedBytes }
        let fraction = total > 0 ? Double(done) / Double(total) : 0
        ProgressRing(fraction: fraction, indeterminate: known.isEmpty, tint: .cyan)
            .frame(width: 17, height: 17)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DownloadPeek: View {
    let monitor: DownloadMonitor

    var body: some View {
        let first = monitor.activeItems.first
        HStack(spacing: 6) {
            Text(first?.displayName ?? "")
                .lineLimit(1)
                .truncationMode(.middle)
            if let first {
                Text(ByteText.detail(for: first))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color(white: 0.84).opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 10)
    }
}

struct DownloadDoneLeading: View {
    let item: DownloadItem

    var body: some View {
        Image(nsImage: FileIcons.icon(for: item))
            .resizable()
            .interpolation(.high)
            .frame(width: 20, height: 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DownloadDoneTrailing: View {
    let item: DownloadItem

    var body: some View {
        Image(systemName: item.state == .finished ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(item.state == .finished ? .green : .red)
            .symbolEffect(.bounce, value: item.id)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct DownloadDonePeek: View {
    let item: DownloadItem

    var body: some View {
        Text(item.state == .finished ? item.displayName : "\(item.displayName) failed")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(white: 0.84).opacity(0.85))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
    }
}

// MARK: Downloads page

struct DownloadsPage: View {
    let monitor: DownloadMonitor

    var body: some View {
        if monitor.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text("No Recent Downloads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                HStack {
                    Text(summary)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    if monitor.items.contains(where: { $0.state != .active }) {
                        Button("Clear") { withAnimation(.notchSnappy) { monitor.clearFinished() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 9)
                            .frame(height: 20)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(monitor.items) { item in
                            DownloadRow(item: item, monitor: monitor)
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        let active = monitor.activeItems.count
        return active > 0 ? "\(active) downloading" : "\(monitor.items.count) recent"
    }
}

struct DownloadRow: View {
    let item: DownloadItem
    let monitor: DownloadMonitor
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: FileIcons.icon(for: item))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .opacity(item.state == .failed ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.state == .active {
                    NotchProgressBar(value: item.isIndeterminate ? 0.05 : item.fraction, style: .white, tint: .cyan, height: 4)
                }
                Text(ByteText.detail(for: item))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(item.state == .failed ? .red.opacity(0.8) : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.state == .finished {
                RowButton(symbol: "magnifyingglass", help: "Show in Finder") { reveal() }
                RowButton(symbol: "tray.and.arrow.down", help: "Add to File Tray") { addToTray() }
            } else if item.state == .failed {
                RowButton(symbol: "xmark", help: "Remove") { monitor.remove(item.id) }
            } else {
                Text(item.isIndeterminate ? "" : "\(Int(item.fraction * 100))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHovering ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture { if item.state == .finished { NSWorkspace.shared.open(item.fileURL) } }
        .onDrag {
            guard item.state == .finished else { return NSItemProvider() }
            return NSItemProvider(object: item.fileURL as NSURL)
        }
        .contextMenu {
            if item.state == .finished {
                Button("Open") { NSWorkspace.shared.open(item.fileURL) }
                Button("Show in Finder") { reveal() }
                Button("Add to File Tray") { addToTray() }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([item.fileURL as NSURL])
                }
                Divider()
            }
            if item.state != .active {
                Button("Remove from List") { monitor.remove(item.id) }
            }
        }
        .help(item.fileURL.path)
    }

    private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }

    /// Hands the file to whichever feature handles drops on the notch (the File Tray).
    private func addToTray() {
        guard let provider = NSItemProvider(contentsOf: item.fileURL) else { return }
        _ = NotchRegistry.shared.dropHandler?([provider])
    }
}

private struct RowButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 0.95 : 0.6))
                .frame(width: 24, height: 24)
                .background(.white.opacity(isHovering ? 0.15 : 0.07), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}
