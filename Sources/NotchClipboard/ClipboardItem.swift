import CryptoKit
import Foundation

struct ClipboardItem: Identifiable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text, richText, url, file, image
    }

    let id: UUID
    var kind: Kind
    var date: Date
    var isPinned = false
    var preview: String
    /// Plain text for text and rich text, the absolute string for URLs.
    var text: String?
    var filePaths: [String]?
    /// Pasteboard type of the payload: RTF for rich text, PNG or TIFF for images.
    var dataType: String?
    /// Identical content shares a signature, which is how duplicates are found.
    var signature: String

    /// Kept out of the JSON index; persisted as separate files.
    var data: Data?
    var thumbnailPNG: Data?

    enum CodingKeys: String, CodingKey {
        case id, kind, date, isPinned, preview, text, filePaths, dataType, signature
    }

    init(kind: Kind, preview: String, text: String? = nil, filePaths: [String]? = nil, dataType: String? = nil, signature: String, data: Data? = nil, thumbnailPNG: Data? = nil, date: Date = Date()) {
        id = UUID()
        self.kind = kind
        self.date = date
        self.preview = preview
        self.text = text
        self.filePaths = filePaths
        self.dataType = dataType
        self.signature = signature
        self.data = data
        self.thumbnailPNG = thumbnailPNG
    }

    var url: URL? {
        guard kind == .url, let text else { return nil }
        return URL(string: text)
    }

    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }

    func matches(_ query: String) -> Bool {
        if preview.localizedCaseInsensitiveContains(query) { return true }
        if let text, text.localizedCaseInsensitiveContains(query) { return true }
        return (filePaths ?? []).contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func preview(forText text: String) -> String {
        let collapsed = text.prefix(600).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.prefix(200))
    }

    static func preview(for url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        return path.isEmpty || path == "/" ? host : host + path
    }

    static func preview(forFiles urls: [URL]) -> String {
        guard let first = urls.first else { return "" }
        let name = FileManager.default.displayName(atPath: first.path)
        return urls.count > 1 ? "\(name) and \(urls.count - 1) more" : name
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    /// Only plain web links count as URLs; anything else copied as text stays text.
    static func webURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host() != nil else { return nil }
        return url
    }
}
