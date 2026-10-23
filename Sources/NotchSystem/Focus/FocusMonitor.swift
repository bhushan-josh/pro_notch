import Foundation

/// Watches the Focus database directory and file, with a slow poll as a fallback
/// for when the watchers cannot be opened (no Full Disk Access yet) or miss an atomic replace.
@MainActor
final class FocusMonitor {
    var onReading: ((FocusReadResult) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pollTask: Task<Void, Never>?
    private var pendingReload: Task<Void, Never>?
    private var readGeneration = 0

    func start() {
        guard pollTask == nil else { return }
        installWatchers()
        reload()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                self.installWatchers()
                self.reload()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        pendingReload?.cancel()
        pendingReload = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
    }

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
            self.onReading?(reading)
        }
    }
}
