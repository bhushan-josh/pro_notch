import AppKit
import UniformTypeIdentifiers

enum DropPayload: Sendable {
    /// An existing file on disk, stored according to the storage mode.
    case file(URL)
    /// Dragged content that is not a file yet (an image, some text, a link).
    case data(Data, name: String)
}

enum DropLoader {
    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .text, .data]

    static func load(_ providers: [NSItemProvider]) async -> [DropPayload] {
        var payloads: [DropPayload] = []
        for provider in providers {
            if let payload = await load(provider) { payloads.append(payload) }
        }
        return payloads
    }

    private static func load(_ provider: NSItemProvider) async -> DropPayload? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadURL(provider, type: .fileURL), url.isFileURL {
            return .file(url)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(provider, type: .url) {
            if url.isFileURL { return .file(url) }
            return webloc(for: url, suggestedName: provider.suggestedName)
        }
        if let type = firstType(of: provider, conformingTo: .image),
           let data = await loadData(provider, type: type) {
            return image(data: data, type: type, suggestedName: provider.suggestedName)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadText(provider) {
            let name = provider.suggestedName ?? textFileName(for: text)
            return .data(Data(text.utf8), name: withExtension(name, "txt"))
        }
        if let type = firstType(of: provider, conformingTo: .data),
           let data = await loadData(provider, type: type) {
            let fallback = "Item" + (type.preferredFilenameExtension.map { ".\($0)" } ?? "")
            return .data(data, name: provider.suggestedName.map { withExtension($0, type.preferredFilenameExtension) } ?? fallback)
        }
        return nil
    }

    private static func firstType(of provider: NSItemProvider, conformingTo parent: UTType) -> UTType? {
        provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first { $0.conforms(to: parent) }
    }

    private static func loadURL(_ provider: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                let url: URL? = switch item {
                case let url as URL: url
                case let data as Data: URL(dataRepresentation: data, relativeTo: nil)
                case let string as String: URL(string: string)
                default: nil
                }
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    private static func image(data: Data, type: UTType, suggestedName: String?) -> DropPayload {
        let base = suggestedName.map { ($0 as NSString).deletingPathExtension } ?? "Image \(timestamp())"
        if type.conforms(to: .tiff),
           let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return .data(png, name: base + ".png")
        }
        return .data(data, name: base + "." + (type.preferredFilenameExtension ?? "png"))
    }

    private static func webloc(for url: URL, suggestedName: String?) -> DropPayload? {
        let plist: [String: String] = ["URL": url.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return nil }
        let name = suggestedName ?? url.host() ?? "Link"
        return .data(data, name: withExtension(name, "webloc"))
    }

    private static func textFileName(for text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces).prefix(40)
        return trimmed.isEmpty ? "Text \(timestamp())" : String(trimmed)
    }

    private static func withExtension(_ name: String, _ ext: String?) -> String {
        guard let ext, (name as NSString).pathExtension.lowercased() != ext.lowercased() else { return name }
        return name + "." + ext
    }

    private static func timestamp() -> String {
        Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
    }
}

/// Turns payloads into files on disk. Runs off the main actor because copies can be large.
enum TrayFileWriter {
    static func makeItem(from payload: DropPayload, mode: FileTrayStorageMode, root: URL) async -> FileTrayItem? {
        let fm = FileManager.default
        switch payload {
        case .file(let url):
            guard fm.fileExists(atPath: url.path) else { return nil }
            if mode == .reference || isInside(url, root: root) {
                return FileTrayItem(url: url, isOwned: false, sourcePath: url.path)
            }
            let id = UUID()
            guard let folder = makeFolder(id: id, root: root) else { return nil }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            do {
                try fm.copyItem(at: url, to: destination)
            } catch {
                try? fm.removeItem(at: folder)
                NSLog("File tray copy failed: \(error)")
                return nil
            }
            return FileTrayItem(id: id, url: destination, isOwned: true, sourcePath: url.path)
        case .data(let data, let name):
            let id = UUID()
            guard let folder = makeFolder(id: id, root: root) else { return nil }
            let destination = folder.appendingPathComponent(sanitized(name))
            do {
                try data.write(to: destination, options: .atomic)
            } catch {
                try? fm.removeItem(at: folder)
                NSLog("File tray write failed: \(error)")
                return nil
            }
            return FileTrayItem(id: id, url: destination, isOwned: true, sourcePath: nil)
        }
    }

    /// Temporary files for content dropped straight onto the AirDrop target.
    static func temporaryFile(for payload: DropPayload) -> URL? {
        switch payload {
        case .file(let url):
            return url
        case .data(let data, let name):
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NotchAirDrop", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(sanitized(name))
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
    }

    static func isInside(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.hasPrefix(rootPath)
    }

    private static func makeFolder(id: UUID, root: URL) -> URL? {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            NSLog("File tray folder creation failed: \(error)")
            return nil
        }
    }

    private static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "Item" + cleaned : cleaned
    }
}
