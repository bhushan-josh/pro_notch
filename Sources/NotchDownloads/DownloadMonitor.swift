import AppKit
import NotchCore
import Observation
import os

private let downloadLog = Logger(subsystem: "com.personal.DynamicNotch", category: "downloads")

struct DownloadItem: Identifiable, Equatable {
    enum State: Equatable {
        case active, finished, failed
    }

    let id: UUID
    /// The file the browser is writing, often a partial like "name.crdownload" or "name.download".
    var partialURL: URL
    var displayName: String
    var totalBytes: Int64
    var completedBytes: Int64
    var fraction: Double
    var state = State.active
    var startedAt = Date()
    var finishedAt: Date?
    var finalURL: URL?
    var bytesPerSecond: Double = 0

    var isIndeterminate: Bool { totalBytes <= 0 }

    var remainingTime: TimeInterval? {
        guard state == .active, totalBytes > 0, bytesPerSecond > 1 else { return nil }
        return Double(totalBytes - completedBytes) / bytesPerSecond
    }

    /// The file to open or reveal: the finished file when known, otherwise the partial.
    var fileURL: URL { finalURL ?? partialURL }
}

/// Watches folders for downloads by subscribing to the file progress browsers publish for Finder's progress bars.
/// Safari, Chrome, Brave, Firefox and other apps that report to Finder all appear here.
@MainActor
@Observable
final class DownloadMonitor {
    private(set) var items: [DownloadItem] = []

    @ObservationIgnored var onStart: ((DownloadItem) -> Void)?
    @ObservationIgnored var onFinish: ((DownloadItem) -> Void)?
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private var subscriptions: [Any] = []
    @ObservationIgnored private var observers: [UUID: [NSKeyValueObservation]] = [:]
    @ObservationIgnored private var samples: [UUID: (time: Date, bytes: Int64)] = [:]
    @ObservationIgnored private var pendingUpdate = false
    @ObservationIgnored private var pruneTimer: Timer?

    nonisolated private static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]

    var activeItems: [DownloadItem] { items.filter { $0.state == .active } }

    func start() {
        stop()
        for folder in DownloadsSettings.folders {
            let token = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
                let id = UUID()
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.track(progress, id: id) } }
                return {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(id: id, progress: progress) } }
                }
            }
            subscriptions.append(token)
        }
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneOld() }
        }
    }

    func stop() {
        subscriptions.forEach(Progress.removeSubscriber)
        subscriptions.removeAll()
        observers.removeAll()
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    func clearFinished() {
        items.removeAll { $0.state != .active }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id && $0.state != .active }
    }

    // MARK: Tracking

    private func track(_ progress: Progress, id: UUID) {
        let kind = progress.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind
        guard kind == nil || kind == .downloading else { return }
        guard let url = (progress.userInfo[.fileURLKey] as? URL) ?? progress.fileURL else { return }

        let item = DownloadItem(
            id: id,
            partialURL: url,
            displayName: Self.displayName(for: url),
            totalBytes: progress.totalUnitCount,
            completedBytes: progress.completedUnitCount,
            fraction: progress.fractionCompleted
        )
        let replaced = items.filter { existing in
            existing.state == .active && (existing.partialURL == url || Self.isPlaceholder(existing, replacedBy: item))
        }
        for old in replaced { forget(old.id) }
        items.removeAll { old in replaced.contains { $0.id == old.id } }
        items.insert(item, at: 0)
        samples[id] = (Date(), progress.completedUnitCount)
        downloadLog.notice("started \(item.displayName, privacy: .public) total=\(item.totalBytes, privacy: .public)")
        onStart?(items[0])

        observers[id] = [
            progress.observe(\.completedUnitCount) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleUpdate() } }
            },
            progress.observe(\.totalUnitCount) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleUpdate() } }
            },
        ]
        progressByID[id] = progress
    }

    @ObservationIgnored private var progressByID: [UUID: Progress] = [:]

    /// Progress objects can update thousands of times a second; fold them into ~8 UI updates per second.
    private func scheduleUpdate() {
        guard !pendingUpdate else { return }
        pendingUpdate = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingUpdate = false
                self?.refreshFromProgress()
            }
        }
    }

    private func refreshFromProgress() {
        let now = Date()
        for index in items.indices where items[index].state == .active {
            let id = items[index].id
            guard let progress = progressByID[id] else { continue }
            let completed = progress.completedUnitCount
            syncURL(of: index, from: progress)
            items[index].totalBytes = progress.totalUnitCount
            items[index].completedBytes = completed
            items[index].fraction = progress.totalUnitCount > 0 ? progress.fractionCompleted : 0
            if let sample = samples[id], now.timeIntervalSince(sample.time) >= 1 {
                let rate = Double(completed - sample.bytes) / now.timeIntervalSince(sample.time)
                let previous = items[index].bytesPerSecond
                items[index].bytesPerSecond = previous > 0 ? previous * 0.6 + max(rate, 0) * 0.4 : max(rate, 0)
                samples[id] = (now, completed)
            }
        }
        onUpdate?()
    }

    private func finish(id: UUID, progress: Progress) {
        forget(id)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        syncURL(of: index, from: progress)
        var item = items[index]
        let finalURL = Self.finalURL(for: item.partialURL) ?? Self.recentlyFinished(near: item)
        let completed = !progress.isCancelled && finalURL != nil
            && (item.totalBytes <= 0 || progress.completedUnitCount >= item.totalBytes || progress.fractionCompleted >= 0.999)
        item.state = completed ? .finished : .failed
        item.finalURL = finalURL
        item.finishedAt = Date()
        if completed {
            item.fraction = 1
            item.completedBytes = max(item.completedBytes, item.totalBytes)
            if let finalURL { item.displayName = finalURL.lastPathComponent }
        }
        items[index] = item
        downloadLog.notice("finished \(item.displayName, privacy: .public) state=\(String(describing: item.state), privacy: .public)")
        onFinish?(item)
    }

    private func forget(_ id: UUID) {
        observers.removeValue(forKey: id)
        progressByID.removeValue(forKey: id)
        samples.removeValue(forKey: id)
    }

    /// An "Unconfirmed 123.crdownload" entry that a browser re-published under the real name.
    nonisolated static func isPlaceholder(_ old: DownloadItem, replacedBy new: DownloadItem) -> Bool {
        old.displayName.hasPrefix("Unconfirmed ")
            && old.partialURL.deletingLastPathComponent() == new.partialURL.deletingLastPathComponent()
            && old.totalBytes > 0 && old.totalBytes == new.totalBytes
    }

    /// Chrome-based browsers start with "Unconfirmed 123.crdownload" and rename once the real name is known.
    private func syncURL(of index: Int, from progress: Progress) {
        guard let url = (progress.userInfo[.fileURLKey] as? URL) ?? progress.fileURL, url != items[index].partialURL else { return }
        items[index].partialURL = url
        items[index].displayName = Self.displayName(for: url)
    }

    private func pruneOld() {
        let cutoff = Date().addingTimeInterval(-Defaults[DownloadsSettings.keepRecentHours] * 3600)
        items.removeAll { $0.state != .active && ($0.finishedAt ?? .distantFuture) < cutoff }
    }

    // MARK: File names

    nonisolated static func isPartial(_ url: URL) -> Bool {
        partialExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func displayName(for url: URL) -> String {
        isPartial(url) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    /// Fallback when the partial's name did not carry the final one: the newest same-sized file written just now.
    nonisolated static func recentlyFinished(near item: DownloadItem) -> URL? {
        let folder = item.partialURL.deletingLastPathComponent()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return nil }
        let cutoff = Date().addingTimeInterval(-10)
        return contents
            .filter { !isPartial($0) }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate, modified > cutoff else { return nil }
                if item.totalBytes > 0, let size = values.fileSize, Int64(size) != item.totalBytes { return nil }
                return (url, modified)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// Where the finished file ended up: the partial's name without its temporary extension, or the file itself.
    nonisolated static func finalURL(for url: URL) -> URL? {
        let fileManager = FileManager.default
        if isPartial(url) {
            let target = url.deletingPathExtension()
            return fileManager.fileExists(atPath: target.path) ? target : nil
        }
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }
}
