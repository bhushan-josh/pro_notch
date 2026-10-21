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
    private static let expressions: [(MeetingProvider, NSRegularExpression)] = MeetingProvider.allCases.compactMap { provider in
        (try? NSRegularExpression(pattern: provider.pattern, options: [.caseInsensitive])).map { (provider, $0) }
    }

    /// Checks the sources in order, so an explicit event URL wins over a link buried in the notes.
    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let sources = [url?.absoluteString, location, notes].compactMap { $0 }.filter { !$0.isEmpty }
        for text in sources {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    private static func firstLink(in text: String) -> MeetingLink? {
        let range = NSRange(text.startIndex..., in: text)
        var best: (location: Int, link: MeetingLink)?
        for (provider, expression) in expressions {
            guard let match = expression.firstMatch(in: text, range: range),
                  let swiftRange = Range(match.range, in: text) else { continue }
            let raw = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)>]"))
            guard let url = URL(string: raw) else { continue }
            if best == nil || match.range.location < best!.location {
                best = (match.range.location, MeetingLink(provider: provider, url: url))
            }
        }
        return best?.link
    }
}
