import Foundation
import UniformTypeIdentifiers

public struct FileTrayItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var url: URL
    public var name: String
    public var size: Int64?
    public var dateAdded: Date
    public var typeIdentifier: String
    /// The file lives in the tray folder and is deleted with the item.
    public var isOwned: Bool
    /// Path the file was dropped from, used to ignore duplicate drops.
    public var sourcePath: String?

    public var contentType: UTType { UTType(typeIdentifier) ?? .item }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public var formattedSize: String? {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    init(id: UUID = UUID(), url: URL, isOwned: Bool, sourcePath: String?) {
        self.id = id
        self.url = url
        self.isOwned = isOwned
        self.sourcePath = sourcePath
        self.dateAdded = Date()
        let values = try? url.resourceValues(forKeys: [.localizedNameKey, .fileSizeKey, .contentTypeKey, .isDirectoryKey])
        self.name = values?.localizedName ?? url.lastPathComponent
        self.size = values?.isDirectory == true ? nil : values?.fileSize.map(Int64.init)
        self.typeIdentifier = (values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data).identifier
    }
}
