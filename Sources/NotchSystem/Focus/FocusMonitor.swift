import Foundation

/// Watches the Focus database directory and file, with a slow poll as a fallback
/// for when the watchers cannot be opened (no Full Disk Access yet).
@MainActor
final class FocusMonitor {
    var onReading: ((FocusReadResult) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var pendingReload: Task<Void, Never>?
    private var readGeneration = 0
    private var isRunning = false
    private var hasAccess = true

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installWatchers()
        reload()
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        pendingReload?.cancel()
        pendingReload = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

    /// The directory watcher sees the assertions file appear, so a missing file needs no watcher of its own.
    private func installWatchers() {
        if directorySource == nil {
            directorySource = makeSource(path: FocusStore.directory.path, mask: [.write, .delete, .rename]) { [weak self] event in
                guard let self else { return }
                if !event.isDisjoint(with: [.delete, .rename]) {
                    self.directorySource?.cancel()
                    self.directorySource = nil
                }
                self.scheduleReload()
            }
        }
        if fileSource == nil {
            fileSource = makeSource(path: FocusStore.assertionsURL.path, mask: [.write, .extend, .attrib, .delete, .rename]) { [weak self] event in
                guard let self else { return }
                // The system replaces the file atomically, so the old descriptor goes stale on rename/delete.
                if !event.isDisjoint(with: [.delete, .rename]) {
                    self.fileSource?.cancel()
                    self.fileSource = nil
                }
                self.scheduleReload()
            }
        }
        updatePolling()
    }

    /// The watchers may open without Full Disk Access, so keep polling until a read succeeds.
    private func updatePolling() {
        let watching = directorySource != nil
            && (fileSource != nil || !FileManager.default.fileExists(atPath: FocusStore.assertionsURL.path))
        if watching, hasAccess {
            pollTask?.cancel()
            pollTask = nil
        } else if isRunning, pollTask == nil {
            pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.pollTask = nil
                self.installWatchers()
                self.reload()
            }
        }
    }

    private func makeSource(
        path: String,
        mask: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: .main)
        source.setEventHandler { [weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated { handler(event) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.installWatchers()
            self.reload()
        }
    }

    private func reload() {
        readGeneration += 1
        let generation = readGeneration
        Task { [weak self] in
            let reading = await Task.detached(priority: .utility) { FocusStore.read() }.value
            guard let self, generation == self.readGeneration else { return }
            self.hasAccess = reading != .noAccess
            self.updatePolling()
            self.onReading?(reading)
        }
    }
}
