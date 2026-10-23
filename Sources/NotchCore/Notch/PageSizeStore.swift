import SwiftUI
import Observation

/// Size limits for an expanded page the user can resize. Sizes are the whole open island, camera row included.
public struct PageResize: Sendable {
    public var minSize: CGSize
    public var maxSize: CGSize

    public init(minSize: CGSize, maxSize: CGSize) {
        self.minSize = minSize
        self.maxSize = maxSize
    }

    func clamp(_ size: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minSize.width), maxSize.width),
            height: min(max(size.height, minSize.height), maxSize.height)
        )
    }
}

/// Remembers the size the user dragged each resizable page to.
@MainActor
@Observable
public final class PageSizeStore {
    public static let shared = PageSizeStore()

    private var sizes: [String: CGSize] = [:]
    /// Parsed UserDefaults values; looked up on every open-island render.
    @ObservationIgnored private var stored: [String: CGSize?] = [:]

    private init() {}

    private static func key(_ pageID: String) -> String { "notch.pageSize.\(pageID)" }

    public func size(for pageID: String) -> CGSize? {
        if let size = sizes[pageID] { return size }
        if let cached = stored[pageID] { return cached }
        let parts = Defaults.store.string(forKey: Self.key(pageID))?.split(separator: ",").compactMap { Double($0) } ?? []
        let size = parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        stored[pageID] = size
        return size
    }

    func setLive(_ size: CGSize, for pageID: String) {
        sizes[pageID] = size
    }

    func persist(_ pageID: String) {
        guard let size = sizes[pageID] else { return }
        Defaults.store.set("\(Int(size.width)),\(Int(size.height))", forKey: Self.key(pageID))
    }

    public func reset(_ pageID: String) {
        sizes.removeValue(forKey: pageID)
        stored[pageID] = .some(nil)
        Defaults.store.removeObject(forKey: Self.key(pageID))
    }
}
