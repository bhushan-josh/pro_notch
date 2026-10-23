import Foundation

enum MeetingProvider: String, CaseIterable, Sendable {
    case zoom, googleMeet, teams, webex, faceTime

    var title: String {
        switch self {
        case .zoom: "Zoom"
        case .googleMeet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .faceTime: "FaceTime"
        }
    }

    var symbol: String { "video.fill" }

    fileprivate var pattern: String {
        switch self {
        case .zoom:
            #"(?:https?://[\w.-]*zoom\.us/(?:j|my|w|s|wc)/[^\s<>"']+)|(?:zoommtg://[^\s<>"']+)"#
        case .googleMeet:
            #"https?://meet\.google\.com/[a-z]{3,4}-[a-z]{4}-[a-z]{3,4}(?:\?[^\s<>"']*)?"#
        case .teams:
            #"https?://(?:teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet)/[^\s<>"']+"#
        case .webex:
            #"https?://[\w.-]+\.webex\.com/[^\s<>"']+"#
        case .faceTime:
            #"https?://facetime\.apple\.com/join[^\s<>"']+"#
        }
    }
}

struct MeetingLink: Equatable, Sendable {
    var provider: MeetingProvider
    var url: URL
}

enum MeetingLinks {
    private static let providers = MeetingProvider.allCases
    /// One capture group per provider, so a single scan finds the earliest link of any kind.
    private static let expression = try? NSRegularExpression(
        pattern: providers.map { "(\($0.pattern))" }.joined(separator: "|"),
        options: [.caseInsensitive]
    )

    /// Checks the sources in order, so an explicit event URL wins over a link buried in the notes.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let sources = [url?.absoluteString, location, notes].compactMap { $0 }.filter { !$0.isEmpty }
        for text in sources {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    private static func firstLink(in text: String) -> MeetingLink? {
        guard let expression else { return nil }
        var link: MeetingLink?
        expression.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            guard let match,
                  let group = providers.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound }),
                  let swiftRange = Range(match.range, in: text) else { return }
            let raw = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>]"))
            guard let url = URL(string: raw) else { return }
            link = MeetingLink(provider: providers[group], url: url)
            stop.pointee = true
        }
        return link
    }
}
