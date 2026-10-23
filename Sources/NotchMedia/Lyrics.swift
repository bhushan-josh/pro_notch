import Foundation
import NotchCore
import Observation

struct Lyrics: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        var time: TimeInterval
        /// Empty for an instrumental break.
        var text: String
    }

    /// Timed lines in order; empty when only plain lyrics exist.
    var lines: [Line] = []
    var plain: [String] = []

    var isSynced: Bool { !lines.isEmpty }

    /// The last line starting at or before `time`; nil before the first line.
    func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0
        var high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    init?(synced: String?, plain: String?) {
        if let synced { lines = Self.parseLRC(synced) }
        if lines.isEmpty, let plain {
            let rows = plain.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            var collapsed: [String] = []
            for row in rows where !(row.isEmpty && (collapsed.last?.isEmpty ?? true)) { collapsed.append(row) }
            while collapsed.last?.isEmpty == true { collapsed.removeLast() }
            self.plain = collapsed
        } else {
            self.plain = lines.map(\.text)
        }
        guard !lines.isEmpty || !self.plain.isEmpty else { return nil }
    }

    static func parseLRC(_ text: String) -> [Line] {
        var result: [Line] = []
        var offset: TimeInterval = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            var rest = raw.drop { $0 == " " || $0 == "\t" }
            var times: [TimeInterval] = []
            while rest.first == "[", let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = timestamp(tag) {
                    times.append(time)
                } else if tag.lowercased().hasPrefix("offset:"),
                          let ms = Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            var line = String(rest)
            if line.contains("<") {
                line = line.replacingOccurrences(of: #"<\d+:\d+(?:[.:]\d+)?>"#, with: "", options: .regularExpression)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            for time in times { result.append(Line(time: time, text: line)) }
        }
        // A positive [offset:] tag means the lyrics should appear earlier.
        if offset != 0 {
            for index in result.indices { result[index].time = max(0, result[index].time - offset) }
        }
        result.sort { $0.time < $1.time }
        var cleaned: [Line] = []
        for line in result where !(line.text.isEmpty && (cleaned.last?.text.isEmpty ?? true)) { cleaned.append(line) }
        return cleaned.contains { !$0.text.isEmpty } ? cleaned : []
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss:xx"; nil for metadata tags like "ar:Artist".
    private static func timestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]), let seconds = Double(parts[1]),
              minutes >= 0, seconds >= 0 else { return nil }
        var time = minutes * 60 + seconds
        if parts.count == 3 {
            guard let fraction = Double("0." + parts[2]) else { return nil }
            time += fraction
        }
        return time
    }
}

/// Lookups against LRCLIB, a free lyrics database that needs no key.
enum LRCLIB {
    struct Query: Sendable {
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
    }

    enum Outcome: Sendable {
        case found(Lyrics)
        case missing
        /// Network or server trouble; worth trying again later.
        case failed
    }

    private struct Record: Decodable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?

        var lyrics: Lyrics? { Lyrics(synced: syncedLyrics, plain: plainLyrics) }
        var hasSynced: Bool { !(syncedLyrics ?? "").isEmpty }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "DynamicNotch/1.0 (personal)"]
        configuration.timeoutIntervalForRequest = 10
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ query: Query) async -> Outcome {
        var items = [
            URLQueryItem(name: "artist_name", value: query.artist),
            URLQueryItem(name: "track_name", value: query.title),
        ]
        if !query.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: query.album)) }
        items.append(URLQueryItem(name: "duration", value: String(Int(query.duration.rounded()))))

        switch await request("get", items) {
        case .failure:
            return .failed
        case .success(let data?):
            if let record = try? JSONDecoder().decode(Record.self, from: data) {
                if let lyrics = record.lyrics { return .found(lyrics) }
                if record.instrumental == true { return .missing }
            }
        case .success(nil):
            break
        }

        let search = [
            URLQueryItem(name: "track_name", value: TitleCleaner.clean(query.title)),
            URLQueryItem(name: "artist_name", value: query.artist),
        ]
        switch await request("search", search) {
        case .failure:
            return .failed
        case .success(nil):
            return .missing
        case .success(let data?):
            guard let records = try? JSONDecoder().decode([Record].self, from: data) else { return .missing }
            let best = records
                .compactMap { record -> (record: Record, gap: Double)? in
                    guard record.instrumental != true, let duration = record.duration else { return nil }
                    let gap = abs(duration - query.duration)
                    return gap <= 5 ? (record, gap) : nil
                }
                .min { lhs, rhs in
                    lhs.record.hasSynced != rhs.record.hasSynced ? lhs.record.hasSynced : lhs.gap < rhs.gap
                }
            return best?.record.lyrics.map(Outcome.found) ?? .missing
        }
    }

    private enum Failure: Error { case unavailable }

    /// The body on success, nil on 404, failure for anything else.
    private static func request(_ endpoint: String, _ items: [URLQueryItem]) async -> Result<Data?, Failure> {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")
        components?.queryItems = items
        guard let url = components?.url,
              let (data, response) = try? await session.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failure(.unavailable) }
        if status == 404 { return .success(nil) }
        return status < 300 ? .success(data) : .failure(.unavailable)
    }
}

/// Lyrics for whatever MediaManager is playing, fetched once per song and kept in a small LRU.
@MainActor
@Observable
final class LyricsManager {
    static let shared = LyricsManager()

    /// Lyrics for the current track; nil while loading or when there are none.
    private(set) var lyrics: Lyrics?
    private(set) var isEnabled = false
    /// The live strip below the closed notch is wanted.
    private(set) var showsUnderNotch = false
    /// Seconds added to the lyric clock; positive shows lines later.
    private(set) var offset: TimeInterval = 0

    private enum Entry {
        case found(Lyrics)
        case missing
    }

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var watcher: SettingsWatcher?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var trackIdentity: String?
    @ObservationIgnored private var requestedKey: String?
    @ObservationIgnored private var cache: [String: Entry] = [:]
    @ObservationIgnored private var cacheOrder: [String] = []
    private let cacheLimit = 50

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        readSettings()
        watcher = SettingsWatcher([MediaSettings.showLyrics.name, MediaSettings.lyricsUnderNotch.name, MediaSettings.lyricsOffset.name]) { [weak self] in
            guard let self else { return }
            self.readSettings()
            self.update(MediaManager.shared.track)
        }
        update(MediaManager.shared.track)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        watcher = nil
        clear()
    }

    /// The line to show for `track` at `date`, with the user's timing offset applied.
    func lineIndex(in lyrics: Lyrics, track: TrackSnapshot, at date: Date) -> Int? {
        lyrics.lineIndex(at: track.elapsed(at: date) - offset)
    }

    func update(_ track: TrackSnapshot?) {
        guard isStarted, isEnabled, let track, !track.title.isEmpty else {
            clear()
            return
        }
        let key = Self.cacheKey(for: track)
        if track.identity != trackIdentity {
            trackIdentity = track.identity
            task?.cancel()
            task = nil
            requestedKey = nil
            var cached: Lyrics?
            switch touch(key) {
            case .found(let hit):
                cached = hit
                requestedKey = key
            case .missing:
                requestedKey = key
            case nil:
                break
            }
            if lyrics != cached { lyrics = cached }
        }
        // Browser tabs are often videos and podcasts; only fetch for something that looks like a song.
        guard requestedKey != key, !track.artist.isEmpty, track.duration > 0 else { return }
        requestedKey = key
        let query = LRCLIB.Query(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        let identity = track.identity
        task = Task { [weak self] in
            let outcome = await LRCLIB.fetch(query)
            guard let self, !Task.isCancelled, self.trackIdentity == identity else { return }
            switch outcome {
            case .found(let found):
                self.store(.found(found), for: key)
                self.lyrics = found
            case .missing:
                self.store(.missing, for: key)
            case .failed:
                // requestedKey stays set, so this song is retried only after the track changes.
                break
            }
            self.task = nil
        }
    }

    private func readSettings() {
        let enabled = Defaults[MediaSettings.showLyrics]
        let underNotch = enabled && Defaults[MediaSettings.lyricsUnderNotch]
        let offset = Defaults[MediaSettings.lyricsOffset]
        if isEnabled != enabled { isEnabled = enabled }
        if showsUnderNotch != underNotch { showsUnderNotch = underNotch }
        if self.offset != offset { self.offset = offset }
    }

    private func clear() {
        task?.cancel()
        task = nil
        trackIdentity = nil
        requestedKey = nil
        if lyrics != nil { lyrics = nil }
    }

    private static func cacheKey(for track: TrackSnapshot) -> String {
        "\(track.artist.lowercased())|\(track.title.lowercased())"
    }

    private func touch(_ key: String) -> Entry? {
        guard let entry = cache[key] else { return nil }
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        return entry
    }

    private func store(_ entry: Entry, for key: String) {
        cache[key] = entry
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > cacheLimit { cache[cacheOrder.removeFirst()] = nil }
    }
}
