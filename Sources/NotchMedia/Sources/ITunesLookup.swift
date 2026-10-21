import AppKit

/// Fills gaps (artwork for streamed Music tracks, a shareable link) from the public iTunes Search API.
@MainActor
enum ITunesLookup {
    struct Result {
        var artworkURL: URL?
        var trackURL: URL?
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            var artworkUrl100: String?
            var trackViewUrl: String?
        }
        var results: [Item]
    }

    private static var cache: [String: Result] = [:]
    private static var inFlight: [String: Task<Result?, Never>] = [:]

    static func lookup(title: String, artist: String) async -> Result? {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return nil }
        let key = term.lowercased()
        if let cached = cache[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task<Result?, Never> {
            var components = URLComponents(string: "https://itunes.apple.com/search")
            components?.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "1"),
            ]
            guard let url = components?.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let response = try? JSONDecoder().decode(Response.self, from: data),
                  let item = response.results.first else { return nil }
            return Result(
                artworkURL: item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100", with: "600x600")) },
                trackURL: item.trackViewUrl.flatMap(URL.init(string:))
            )
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            if cache.count > 200 { cache.removeAll() }
            cache[key] = result
        }
        return result
    }
}

enum TitleCleaner {
    private static let patterns: [NSRegularExpression] = [
        #"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s[^\)\]]*[\)\]]"#,
        #"\s*[\(\[][^\)\]]*\b(remaster(ed)?|live|version|edit|mix|mono|stereo|deluxe|bonus|anniversary|explicit|clean|acoustic|demo|single|instrumental|official|video|audio|lyrics?|hd|4k)\b[^\)\]]*[\)\]]"#,
        #"\s+[-\u2013]\s+((\d{4}\s+)?remaster(ed)?.*|live\b.*|.*\bversion|.*\bedit|single|ep|mono|stereo|bonus track|.*\bmix)$"#,
        #"\s+(feat\.?|ft\.?)\s.+$"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func clean(_ title: String) -> String {
        var result = title
        for pattern in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = pattern.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? title : result
    }
}
