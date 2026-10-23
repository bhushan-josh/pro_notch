import AppKit
import SwiftUI
import NotchCore
import Observation
import os

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
    @ObservationIgnored var onStart: ((DownloadItem) -> Void)?
    @ObservationIgnored var onFinish: ((DownloadItem) -> Void)?
    @ObservationIgnored var onUpdate: (() -> Void)?
    /// Fires whenever the list goes from empty to non-empty or back.
    @ObservationIgnored var onEmptyChange: ((_ isEmpty: Bool) -> Void)?

    @ObservationIgnored private var subscriptions: [Any] = []
    @ObservationIgnored private var observers: [UUID: [NSKeyValueObservation]] = [:]
    @ObservationIgnored private var samples: [UUID: (time: Date, bytes: Int64)] = [:]
    nonisolated private let pendingUpdate = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var expiryTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastChange: [UUID: Date] = [:]
    @ObservationIgnored private var staleCheck: Task<Void, Never>?

    private(set) var items: [DownloadItem] = [] {
        didSet {
            if items.isEmpty != oldValue.isEmpty { onEmptyChange?(items.isEmpty) }
        }
    }

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
        for item in items { scheduleExpiry(of: item.id) }
    }

    func stop() {
        subscriptions.forEach(Progress.removeSubscriber)
        subscriptions.removeAll()
        observers.removeAll()
        progressByID.removeAll()
        samples.removeAll()
        lastChange.removeAll()
        staleCheck?.cancel()
        staleCheck = nil
        expiryTasks.values.forEach { $0.cancel() }
        expiryTasks.removeAll()
        // Without a subscription these would never update or finish.
        if items.contains(where: { $0.state == .active }) {
            items.removeAll { $0.state == .active }
            onUpdate?()
        }
    }

    func clearFinished() {
        for item in items where item.state != .active { expiryTasks.removeValue(forKey: item.id)?.cancel() }
        items.removeAll { $0.state != .active }
    }

    func remove(_ id: UUID) {
        expiryTasks.removeValue(forKey: id)?.cancel()
        items.removeAll { $0.id == id && $0.state != .active }
    }

    private func scheduleExpiry(of id: UUID) {
        let delay = max(5, Defaults[DownloadsSettings.hideFinishedAfter])
        expiryTasks[id]?.cancel()
        expiryTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.expiryTasks.removeValue(forKey: id)
            withAnimation(.notchSnappy) { self.items.removeAll { $0.id == id && $0.state != .active } }
        }
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
        lastChange[id] = Date()
        if replaced.isEmpty { onStart?(items[0]) } else { onUpdate?() }

        observers[id] = [
            progress.observe(\.completedUnitCount) { [weak self] _, _ in self?.scheduleUpdate() },
            progress.observe(\.totalUnitCount) { [weak self] _, _ in self?.scheduleUpdate() },
        ]
        progressByID[id] = progress
        startStaleCheck()
    }

    @ObservationIgnored private var progressByID: [UUID: Progress] = [:]

    /// Progress objects can update thousands of times a second; fold them into ~8 UI updates per second.
    /// Called on the KVO thread, so the main thread only wakes once per batch.
    nonisolated private func scheduleUpdate() {
        let alreadyPending = pendingUpdate.withLock { pending in
            defer { pending = true }
            return pending
        }
        guard !alreadyPending else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingUpdate.withLock { $0 = false }
                self?.refreshFromProgress()
            }
        }
    }

    private func refreshFromProgress() {
        let now = Date()
        var updated = items
        for index in updated.indices where updated[index].state == .active {
            var item = updated[index]
            guard let progress = progressByID[item.id] else { continue }
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            if completed != item.completedBytes { lastChange[item.id] = now }
            Self.syncURL(&item, from: progress)
            item.totalBytes = total
            item.completedBytes = completed
            item.fraction = total > 0 ? progress.fractionCompleted : 0
            if let sample = samples[item.id], now.timeIntervalSince(sample.time) >= 1 {
                let rate = max(Double(completed - sample.bytes) / now.timeIntervalSince(sample.time), 0)
                item.bytesPerSecond = item.bytesPerSecond > 0 ? item.bytesPerSecond * 0.6 + rate * 0.4 : rate
                samples[item.id] = (now, completed)
            }
            updated[index] = item
        }
        if updated != items { items = updated }
        onUpdate?()
    }

    private func finish(id: UUID, progress: Progress, attempt: Int = 0) {
        forget(id)
        guard let index = items.firstIndex(where: { $0.id == id && $0.state == .active }) else { return }
        var item = items[index]
        if Self.syncURL(&item, from: progress) { items[index] = item }
        if let finalURL = Self.finalURL(for: item.partialURL) {
            complete(id: id, progress: progress, attempt: attempt, finalURL: finalURL)
            return
        }
        let snapshot = item
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.recentlyFinished(near: snapshot) }.value
            self?.complete(id: id, progress: progress, attempt: attempt, finalURL: found)
        }
    }

    private func complete(id: UUID, progress: Progress, attempt: Int, finalURL: URL?) {
        // The item may have been removed or replaced while the folder was being searched.
        guard let index = items.firstIndex(where: { $0.id == id && $0.state == .active }) else { return }
        var item = items[index]
        let bytesComplete = item.totalBytes <= 0 || progress.completedUnitCount >= item.totalBytes || progress.fractionCompleted >= 0.999
        // Browsers can unpublish just before renaming "x.crdownload" to "x".
        if finalURL == nil, !progress.isCancelled, bytesComplete, attempt < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.finish(id: id, progress: progress, attempt: attempt + 1) }
            }
            return
        }
        let completed = !progress.isCancelled && finalURL != nil && bytesComplete
        item.state = completed ? .finished : .failed
        item.finalURL = finalURL
        if completed {
            item.fraction = 1
            item.completedBytes = max(item.completedBytes, item.totalBytes)
            if let finalURL { item.displayName = finalURL.lastPathComponent }
        }
        items[index] = item
        scheduleExpiry(of: id)
        onFinish?(item)
    }

    private func forget(_ id: UUID) {
        observers.removeValue(forKey: id)
        progressByID.removeValue(forKey: id)
        samples.removeValue(forKey: id)
        lastChange.removeValue(forKey: id)
    }

    private func startStaleCheck() {
        guard staleCheck == nil else { return }
        staleCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2), tolerance: .seconds(0.5))
                guard !Task.isCancelled, let self else { return }
                if !self.failStaleItems() {
                    self.staleCheck = nil
                    return
                }
                self.decayStalledRates()
            }
        }
    }

    /// Throughput only updates when bytes arrive, so a stalled download would otherwise keep showing its last speed.
    private func decayStalledRates() {
        let now = Date()
        let stalled = items.contains { item in
            guard item.state == .active, item.bytesPerSecond > 0, let last = lastChange[item.id] else { return false }
            return now.timeIntervalSince(last) >= 2
        }
        if stalled { refreshFromProgress() }
    }

    /// Fails downloads whose publisher went away without unpublishing, so they expire. Returns whether any remain active.
    private func failStaleItems() -> Bool {
        let now = Date()
        var changed = false
        for index in items.indices where items[index].state == .active {
            let id = items[index].id
            // Items with no record are waiting in finish(id:progress:attempt:) for the final file.
            guard let last = lastChange[id], now.timeIntervalSince(last) >= 60,
                  !FileManager.default.fileExists(atPath: items[index].partialURL.path) else { continue }
            forget(id)
            items[index].state = .failed
            scheduleExpiry(of: id)
            changed = true
        }
        if changed { onUpdate?() }
        return items.contains { $0.state == .active }
    }

    /// An "Unconfirmed 123.crdownload" entry that a browser re-published under the real name.
    nonisolated static func isPlaceholder(_ old: DownloadItem, replacedBy new: DownloadItem) -> Bool {
        old.displayName.hasPrefix("Unconfirmed ")
            && old.partialURL.deletingLastPathComponent() == new.partialURL.deletingLastPathComponent()
            && old.totalBytes > 0 && old.totalBytes == new.totalBytes
    }

    /// Chrome-based browsers start with "Unconfirmed 123.crdownload" and rename once the real name is known.
    @discardableResult
    private static func syncURL(_ item: inout DownloadItem, from progress: Progress) -> Bool {
        guard let url = (progress.userInfo[.fileURLKey] as? URL) ?? progress.fileURL, url != item.partialURL else { return false }
        item.partialURL = url
        item.displayName = displayName(for: url)
        return true
    }

    // MARK: File names

    nonisolated static func isPartial(_ url: URL) -> Bool {
        partialExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func displayName(for url: URL) -> String {
        isPartial(url) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }

    /// Fallback when the partial's name did not carry the final one: the newest file written just now with the same name or size.
    nonisolated static func recentlyFinished(near item: DownloadItem) -> URL? {
        let folder = item.partialURL.deletingLastPathComponent()
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return nil }
        let cutoff = Date().addingTimeInterval(-10)
        let stem = (item.displayName as NSString).deletingPathExtension.lowercased()
        return contents
            .filter { !isPartial($0) }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      let modified = values.contentModificationDate, modified > cutoff else { return nil }
                let sameName = url.deletingPathExtension().lastPathComponent.lowercased() == stem
                let sameSize = item.totalBytes > 0 && values.fileSize.map { Int64($0) == item.totalBytes } == true
                guard sameName || sameSize else { return nil }
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
