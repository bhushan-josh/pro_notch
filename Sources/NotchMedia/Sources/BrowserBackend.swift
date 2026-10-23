import AppKit
import NotchCore
import Observation

/// Finds the tab that is playing media in any supported browser and controls it with page JavaScript.
///
/// Every browser blocks this until the user turns on "Allow JavaScript from Apple Events";
/// `BrowserAccess` reports that per browser so Settings can explain what to enable.
@MainActor
final class BrowserBackend: PollingBackend {
    enum Browser: String, CaseIterable, Identifiable, Hashable {
        case brave = "com.brave.Browser"
        case chrome = "com.google.Chrome"
        case safari = "com.apple.Safari"
        case edge = "com.microsoft.edgemac"
        case arc = "company.thebrowser.Browser"
        case vivaldi = "com.vivaldi.Vivaldi"
        case opera = "com.operasoftware.Opera"
        case dia = "company.thebrowser.dia"

        var id: String { rawValue }
        var isSafari: Bool { self == .safari }

        var name: String {
            switch self {
            case .brave: "Brave"
            case .chrome: "Chrome"
            case .safari: "Safari"
            case .edge: "Edge"
            case .arc: "Arc"
            case .vivaldi: "Vivaldi"
            case .opera: "Opera"
            case .dia: "Dia"
            }
        }

        var setupHint: String {
            isSafari
                ? "Safari: Settings > Advanced > Show features for web developers, then Develop > Allow JavaScript from Apple Events."
                : "\(name): View > Developer > Allow JavaScript from Apple Events."
        }

        var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) != nil }
        var isRunning: Bool { AppleScriptRunner.isRunning(bundleID: rawValue) }
    }

    struct TabRef: Equatable {
        var browser: Browser
        var windowID: String
        /// Chromium tab id, or the 1-based tab index in Safari.
        var tabID: String
    }

    private struct TabInfo {
        var ref: TabRef
        var isActive: Bool
        var isFrontWindow: Bool
        var url: String
    }

    private var activeTab: TabRef?
    /// Nonzero while user commands run, so a probe batch stops early instead of delaying them on the script queue.
    private var pendingCommands = 0
    /// Restricts playback detection to these browsers; nil allows every supported browser.
    var allowed: Set<Browser>? {
        didSet { if allowed != oldValue { refresh() } }
    }
    private static let maxProbesPerPoll = 10

    private static let mediaHosts = [
        "youtube.com", "youtu.be", "spotify.com", "soundcloud.com", "music.apple.com", "deezer.com", "tidal.com",
        "bandcamp.com", "pandora.com", "twitch.tv", "vimeo.com", "jiosaavn.com", "gaana.com", "wynk.in",
        "audiomack.com", "mixcloud.com", "netflix.com", "primevideo.com", "hotstar.com", "amazon.com/music",
    ]

    init() { super.init(kind: .browser) }

    // Playing polls probe just the playing tab; idle polls list tabs and probe the likely candidates.
    override var playingInterval: TimeInterval { 2 }
    override var idleInterval: TimeInterval { 10 }
    override var watchedBundleIDs: [String] { Browser.allCases.map(\.rawValue) }
    override var capabilities: Set<MediaCapability> { [.seek, .skip] }

    // MARK: Polling

    override func poll() async {
        let running = Browser.allCases.filter { $0.isRunning && (allowed?.contains($0) ?? true) }
        guard !running.isEmpty else {
            activeTab = nil
            publish(nil)
            return
        }

        var paused: (TabRef, TrackSnapshot)?
        if let tab = activeTab, snapshot?.isPlaying == true, running.contains(tab.browser), let track = await read(tab) {
            if track.isPlaying {
                publish(track)
                return
            }
            paused = (tab, track)
        }

        var tabs: [TabInfo] = []
        for browser in running {
            guard pendingCommands == 0 else { return }
            tabs += await listTabs(of: browser)
        }

        var probes = 0
        for tab in ordered(tabs) where probes < Self.maxProbesPerPoll {
            if tab.ref == paused?.0 { continue }
            guard pendingCommands == 0 else { return }
            probes += 1
            guard let track = await read(tab.ref) else { continue }
            if track.isPlaying {
                activeTab = tab.ref
                publish(track)
                return
            }
            if paused == nil || tab.ref == activeTab { paused = (tab.ref, track) }
        }
        if let paused {
            activeTab = paused.0
            publish(paused.1)
        } else {
            activeTab = nil
            publish(nil)
        }
    }

    /// The last playing tab first, then media sites, then the front tab of the browser the user is in.
    private func ordered(_ tabs: [TabInfo]) -> [TabInfo] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        func score(_ tab: TabInfo) -> Int {
            if tab.ref == activeTab { return 0 }
            if Self.isMediaSite(tab.url) { return tab.isActive ? 1 : 2 }
            return tab.isActive && tab.isFrontWindow && tab.ref.browser.rawValue == frontmost ? 3 : 9
        }
        return tabs
            .filter { $0.url.hasPrefix("http") && score($0) < 9 }
            .sorted { score($0) < score($1) }
    }

    private static func isMediaSite(_ url: String) -> Bool {
        let lower = url.lowercased()
        return mediaHosts.contains { lower.contains($0) }
    }

    private func listTabs(of browser: Browser) async -> [TabInfo] {
        // Whole-list reads cost one Apple Event per window instead of two per tab. Windows come front to back.
        let body = browser.isSafari
            ? """
                        set ai to index of current tab of w
                        set urls to URL of every tab of w
                        set ids to {}
                        repeat with i from 1 to count of urls
                            set end of ids to i
                        end repeat
            """
            : """
                        set ai to active tab index of w
                        set ids to id of every tab of w
                        set urls to URL of every tab of w
            """
        let script = """
        set sep to character id 9
        set out to {}
        if application id "\(browser.rawValue)" is running then
            tell application id "\(browser.rawValue)"
                set wids to id of every window
                repeat with wi from 1 to count of wids
                    set wid to item wi of wids
                    try
                        set w to window id wid
        \(body)
                        repeat with i from 1 to count of ids
                            set end of out to (wid as text) & sep & (item i of ids as text) & sep & ((i = ai) as text) & sep & ((wi = 1) as text) & sep & (item i of urls as text)
                        end repeat
                    end try
                end repeat
            end tell
        end if
        set AppleScript's text item delimiters to linefeed
        return out as text
        """
        do {
            let text = try await AppleScriptRunner.run(script).stringValue ?? ""
            BrowserAccess.shared.note(browser, automationAllowed: true)
            return text.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 5 else { return nil }
                return TabInfo(
                    ref: TabRef(browser: browser, windowID: parts[0], tabID: parts[1]),
                    isActive: parts[2] == "true",
                    isFrontWindow: parts[3] == "true",
                    url: parts[4]
                )
            }
        } catch let error as AppleScriptRunner.ScriptError {
            if error.code == -1743 { BrowserAccess.shared.note(browser, automationAllowed: false) }
            return []
        } catch {
            return []
        }
    }

    // MARK: JavaScript

    private func runJS(_ javaScript: String, in tab: TabRef) async -> String? {
        let js = ScriptText.quoted(javaScript)
        let call = tab.browser.isSafari
            ? "do JavaScript \(js) in tab \(tab.tabID) of window id \(tab.windowID)"
            : "execute tab id \(tab.tabID) of window id \(tab.windowID) javascript \(js)"
        let script = """
        if application id "\(tab.browser.rawValue)" is running then
            tell application id "\(tab.browser.rawValue)" to return \(call)
        end if
        return ""
        """
        do {
            let result = try await AppleScriptRunner.run(script).stringValue
            BrowserAccess.shared.note(tab.browser, javaScriptAllowed: true)
            return result
        } catch let error as AppleScriptRunner.ScriptError {
            if error.description.localizedCaseInsensitiveContains("javascript") {
                BrowserAccess.shared.note(tab.browser, javaScriptAllowed: false)
            }
            return nil
        } catch {
            return nil
        }
    }

    private struct Payload: Decodable {
        var t: String?
        var a: String?
        var al: String?
        var c: Double?
        var d: Double?
        var p: Bool?
        var r: Double?
        var art: String?
        var u: String?
    }

    private func read(_ tab: TabRef) async -> TrackSnapshot? {
        guard let json = await runJS(Self.readScript, in: tab), !json.isEmpty,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { return nil }
        var track = TrackSnapshot()
        track.bundleID = tab.browser.rawValue
        track.title = payload.t?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        track.artist = payload.a ?? ""
        track.album = payload.al ?? ""
        track.duration = payload.d ?? 0
        track.elapsed = payload.c ?? 0
        track.timestamp = Date()
        track.rate = payload.r ?? 1
        track.isPlaying = !(payload.p ?? true)
        if let art = payload.art, !art.isEmpty { track.artworkURL = URL(string: art) }
        if let link = payload.u { track.link = URL(string: link) }
        return track
    }

    /// Prefers an unmuted playing element so autoplaying hover previews are ignored, then falls back to Media Session.
    private static let pickElement = #"""
    function __dnPick(){var els=[].slice.call(document.querySelectorAll('video,audio'));for(var i=0;i<els.length;i++){var e=els[i];if(!e.paused&&!e.ended&&!e.muted&&e.readyState>1)return e;}for(var j=0;j<els.length;j++){var f=els[j];if(f.currentTime>0&&!f.ended&&!f.muted&&f.duration>0)return f;}return null;}
    """#

    private static let readScript = pickElement + #"""
    (function(){function secs(s){if(!s)return 0;var p=s.trim().split(':');var v=0;for(var i=0;i<p.length;i++)v=v*60+(parseFloat(p[i])||0);return v;}
    var ms=navigator.mediaSession,m=ms&&ms.metadata,e=__dnPick(),h=location.hostname,st=ms?ms.playbackState:'none';
    if(!e&&!(m&&m.title&&st!=='none'))return '';
    var playing=e?!e.paused:st==='playing',c=e?e.currentTime:0,d=e&&isFinite(e.duration)?e.duration:0;
    if(h.indexOf('spotify.com')>=0){var pp=document.querySelector('[data-testid="playback-position"]'),pd=document.querySelector('[data-testid="playback-duration"]');if(pp&&pd){c=secs(pp.textContent);d=secs(pd.textContent);}var b=document.querySelector('[data-testid="control-button-playpause"]');if(b){var l=(b.getAttribute('aria-label')||'').toLowerCase();if(l)playing=l.indexOf('pause')>=0;}}
    var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}
    if(!art&&h.indexOf('youtube.com')>=0){var v=new URLSearchParams(location.search).get('v');if(v)art='https://i.ytimg.com/vi/'+v+'/hqdefault.jpg';}
    return JSON.stringify({t:(m&&m.title)||document.title,a:(m&&m.artist)||h.replace(/^www\./,''),al:(m&&m.album)||'',c:c,d:d,p:!playing,r:e?e.playbackRate:1,art:art,u:location.href});})()
    """#

    /// Site buttons first (they keep the site's queue and UI in sync), the media element as a fallback.
    private static func commandScript(_ command: String, argument: Double = 0) -> String {
        pickElement + """
        (function(){var h=location.hostname,e=__dnPick(),cmd='\(command)',arg=\(argument);
        function click(s){var b=document.querySelector(s);if(b){b.click();return true;}return false;}
        var spotify=h.indexOf('spotify.com')>=0,ytm=h==='music.youtube.com',yt=!ytm&&h.indexOf('youtube.com')>=0,sc=h.indexOf('soundcloud.com')>=0;
        if(cmd==='toggle'){
          if(e){if(e.paused)e.play();else e.pause();return 'ok';}
          if(spotify&&click('[data-testid="control-button-playpause"]'))return 'ok';
          if(ytm&&click('#play-pause-button'))return 'ok';
          if(sc&&click('.playControl'))return 'ok';
          return '';}
        if(cmd==='next'){
          if(spotify&&click('[data-testid="control-button-skip-forward"]'))return 'ok';
          if(ytm&&click('ytmusic-player-bar .next-button'))return 'ok';
          if(yt&&click('.ytp-next-button'))return 'ok';
          if(sc&&click('.skipControl__next'))return 'ok';
          if(e&&isFinite(e.duration)){e.currentTime=e.duration;return 'ok';}
          return '';}
        if(cmd==='previous'){
          if(spotify&&click('[data-testid="control-button-skip-back"]'))return 'ok';
          if(ytm&&click('ytmusic-player-bar .previous-button'))return 'ok';
          if(sc&&click('.skipControl__previous'))return 'ok';
          if(yt&&e&&e.currentTime<3){var pb=document.querySelector('.ytp-prev-button');if(pb&&pb.offsetParent){pb.click();return 'ok';}}
          if(e){e.currentTime=0;return 'ok';}
          return '';}
        if(cmd==='seek'&&e){e.currentTime=arg;return 'ok';}
        return '';})()
        """
    }

    override func send(_ command: MediaCommand) {
        guard let tab = activeTab else { return }
        let script: String
        switch command {
        case .togglePlayPause:
            script = Self.commandScript("toggle")
            optimistic { $0.isPlaying.toggle() }
        case .next:
            script = Self.commandScript("next")
        case .previous:
            script = Self.commandScript("previous")
            optimistic { $0.elapsed = 0 }
        case .seek(let position):
            script = Self.commandScript("seek", argument: position)
            optimistic { $0.elapsed = position }
        case .setShuffle, .setRepeat, .setLiked:
            return
        }
        pendingCommands += 1
        Task {
            _ = await runJS(script, in: tab)
            pendingCommands -= 1
            refreshSoon(0.6)
        }
    }

    /// Brings the playing tab to the front.
    func revealActiveTab() {
        guard let tab = activeTab else { return }
        let select = tab.browser.isSafari
            ? "set current tab of window id \(tab.windowID) to tab \(tab.tabID) of window id \(tab.windowID)"
            : "set active tab index of window id \(tab.windowID) to (index of tab id \(tab.tabID) of window id \(tab.windowID))"
        let script = """
        tell application id "\(tab.browser.rawValue)"
            \(select)
            set index of window id \(tab.windowID) to 1
            activate
        end tell
        """
        Task { _ = try? await AppleScriptRunner.run(script) }
    }

    /// Runs a harmless script against a browser so Settings can show whether access works.
    func test(_ browser: Browser) async {
        guard browser.isRunning else {
            BrowserAccess.shared.note(browser, running: false)
            return
        }
        BrowserAccess.shared.note(browser, running: true)
        let tabs = await listTabs(of: browser)
        guard let tab = tabs.first(where: { $0.url.hasPrefix("http") }) else { return }
        _ = await runJS("'ok'", in: tab.ref)
    }
}

/// What each browser currently allows, learned from the scripts that have run.
@MainActor
@Observable
final class BrowserAccess {
    static let shared = BrowserAccess()

    struct Status: Equatable {
        var running: Bool?
        var automationAllowed: Bool?
        var javaScriptAllowed: Bool?
    }

    private(set) var statuses: [BrowserBackend.Browser: Status] = [:]

    func note(_ browser: BrowserBackend.Browser, running: Bool? = nil, automationAllowed: Bool? = nil, javaScriptAllowed: Bool? = nil) {
        var status = statuses[browser] ?? Status()
        if let running { status.running = running }
        if let automationAllowed { status.automationAllowed = automationAllowed }
        if let javaScriptAllowed { status.javaScriptAllowed = javaScriptAllowed }
        if statuses[browser] != status { statuses[browser] = status }
    }
}
