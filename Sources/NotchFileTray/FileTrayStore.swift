import AppKit
import NotchCore
import Observation
import QuickLookThumbnailing
import SwiftUI

@MainActor
@Observable
public final class FileTrayStore {
    public private(set) var items: [FileTrayItem] = []
    public private(set) var thumbnails: [UUID: NSImage] = [:]
    public private(set) var updatedAt = Date()

    /// Called after a drop adds at least one item, with the number added.
    @ObservationIgnored var onAdd: ((Int) -> Void)?
    @ObservationIgnored private var thumbnailRequests: Set<UUID> = []

    static let supportFolder = URL.applicationSupportDirectory.appendingPathComponent("Dynamic Notch", isDirectory: true)
    static let trayFolder = supportFolder.appendingPathComponent("FileTray", isDirectory: true)
    private static let indexURL = supportFolder.appendingPathComponent("FileTray.json")

    init() {}

    public var urls: [URL] { items.map(\.url) }

    // MARK: - Adding

    func add(providers: [NSItemProvider]) {
        Task {
            let payloads = await DropLoader.load(providers)
            await add(payloads: payloads)
        }
    }

    func add(payloads: [DropPayload]) async {
        let fresh = payloads.filter { payload in
            guard case .file(let url) = payload else { return true }
            return !contains(url)
        }
        guard !fresh.isEmpty else { return }
        let mode = Defaults[FileTraySettings.storage]
        let root = Self.trayFolder
        var added: [FileTrayItem] = []
        for payload in fresh {
            if let item = await TrayFileWriter.makeItem(from: payload, mode: mode, root: root) {
                added.append(item)
            }
        }
        guard !added.isEmpty else { return }
        withAnimation(.notchSnappy) { items.append(contentsOf: added) }
        trimToLimit()
        touch()
        SystemSound.pop.play()
        Haptics.perform()
        onAdd?(added.count)
    }

    /// Adds files from code (another feature, a service) rather than a drag.
    public func add(urls: [URL]) {
        Task { await add(payloads: urls.map(DropPayload.file)) }
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return items.contains { $0.url.standardizedFileURL.path == path || $0.sourcePath == path }
    }

    func trimToLimit() {
        let limit = max(1, Defaults[FileTraySettings.maxItems])
        guard items.count > limit else { return }
        let overflow = items.prefix(items.count - limit)
        remove(Array(overflow))
    }

    // MARK: - Removing

    public func remove(_ item: FileTrayItem) { remove([item]) }

    public func remove(_ removed: [FileTrayItem]) {
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        withAnimation(.notchSnappy) { items.removeAll { ids.contains($0.id) } }
        removed.forEach { deleteFiles(of: $0); thumbnails[$0.id] = nil }
        touch()
    }

    public func removeAll() { remove(items) }

    /// Drops items whose file was moved or deleted (always in reference mode, and for copies dragged out by moving).
    func pruneMissing() {
        let missing = items.filter { !$0.exists }
        guard !missing.isEmpty else { return }
        remove(missing)
    }

    private func deleteFiles(of item: FileTrayItem) {
        guard item.isOwned else { return }
        let folder = item.url.deletingLastPathComponent()
        // Never delete anything outside our own folder, even if the index on disk was edited.
        guard TrayFileWriter.isInside(folder, root: Self.trayFolder) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Thumbnails

    func loadThumbnail(for item: FileTrayItem) async {
        guard thumbnails[item.id] == nil, !thumbnailRequests.contains(item.id) else { return }
        thumbnailRequests.insert(item.id)
        defer { thumbnailRequests.remove(item.id) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 112, height: 112), scale: scale, representationTypes: .all)
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: item.url.path)
        }
        guard items.contains(where: { $0.id == item.id }) else { return }
        thumbnails[item.id] = image
    }

    // MARK: - Persistence

    func restore() {
        guard Defaults[FileTraySettings.persist] else {
            discardStoredTray()
            return
        }
        guard let data = try? Data(contentsOf: Self.indexURL),
              let saved = try? JSONDecoder().decode([FileTrayItem].self, from: data) else { return }
        items = saved.filter(\.exists)
        removeOrphanedFolders()
        if items.count != saved.count { save() }
    }

    func save() {
        guard Defaults[FileTraySettings.persist] else {
            try? FileManager.default.removeItem(at: Self.indexURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: Self.indexURL, options: .atomic)
        } catch {
            NSLog("File tray save failed: \(error)")
        }
    }

    private func discardStoredTray() {
        try? FileManager.default.removeItem(at: Self.indexURL)
        try? FileManager.default.removeItem(at: Self.trayFolder)
    }

    private func removeOrphanedFolders() {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: Self.trayFolder, includingPropertiesForKeys: nil) else { return }
        let live = Set(items.filter(\.isOwned).map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
        for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
            if !live.contains(folder.standardizedFileURL.path) { try? fm.removeItem(at: folder) }
        }
    }

    private func touch() {
        updatedAt = Date()
        save()
    }

    // MARK: - Actions

    public func revealFolder() {
        try? FileManager.default.createDirectory(at: Self.trayFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.trayFolder)
    }
}
