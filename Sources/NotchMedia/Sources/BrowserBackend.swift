import AppKit
import NotchCore

/// Reads the first playing `<video>`/`<audio>` in the front tab of a browser.
/// Needs "Allow JavaScript from Apple Events" in the browser; without it every script fails and this stays empty.
@MainActor
final class BrowserBackend: PollingBackend {
    enum Browser: String, CaseIterable {
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case dia = "company.thebrowser.dia"

        func script(running javaScript: String) -> String {
            let js = ScriptText.quoted(javaScript)
            let call = switch self {
            case .safari: "do JavaScript \(js) in current tab of front window"
            case .chrome, .dia: "execute active tab of front window javascript \(js)"
            }
            return """
            if application id "\(rawValue)" is running then
                tell application id "\(rawValue)"
                    if (count of windows) is 0 then return ""
                    return \(call)
                end tell
            end if
            return ""
            """
        }
    }

    private var activeBrowser: Browser?

    init() { super.init(kind: .browser) }

    override var playingInterval: TimeInterval { 1.5 }
    override var idleInterval: TimeInterval { 3 }
    override var watchedBundleIDs: [String] { Browser.allCases.map(\.rawValue) }
    override var capabilities: Set<MediaCapability> { [.seek, .skip] }

    private static let findElement = #"""
    function __notchMedia(){var els=Array.prototype.slice.call(document.querySelectorAll('video,audio'));for(var i=0;i<els.length;i++){if(!els[i].paused&&!els[i].ended)return els[i];}for(var j=0;j<els.length;j++){if(els[j].currentTime>0&&!els[j].ended)return els[j];}return null;}
    """#

    private static let readScript = findElement + #"""
    (function(){var e=__notchMedia();if(!e)return '';var m=navigator.mediaSession&&navigator.mediaSession.metadata;var art='';if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}return JSON.stringify({t:(m&&m.title)||document.title,a:(m&&m.artist)||location.hostname.replace(/^www\./,''),al:(m&&m.album)||'',c:e.currentTime,d:isFinite(e.duration)?e.duration:0,p:e.paused,r:e.playbackRate,art:art,u:location.href});})()
    """#

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

    override func poll() async {
        let running = Browser.allCases.filter { AppleScriptRunner.isRunning(bundleID: $0.rawValue) }
        guard !running.isEmpty else {
            activeBrowser = nil
            publish(nil)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ordered = running.sorted { lhs, rhs in
            rank(lhs, frontmost: frontmost) < rank(rhs, frontmost: frontmost)
        }
        for browser in ordered {
            guard let json = await AppleScriptRunner.string(browser.script(running: Self.readScript)),
                  !json.isEmpty,
                  let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { continue }
            activeBrowser = browser
            var track = TrackSnapshot()
            track.bundleID = browser.rawValue
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
            publish(track)
            return
        }
        activeBrowser = nil
        publish(nil)
    }

    private func rank(_ browser: Browser, frontmost: String?) -> Int {
        if browser == activeBrowser { return 0 }
        if browser.rawValue == frontmost { return 1 }
        return 2
    }

    override func send(_ command: MediaCommand) {
        guard let browser = activeBrowser else { return }
        let action: String
        switch command {
        case .togglePlayPause:
            action = "e.paused?e.play():e.pause();"
            optimistic { $0.isPlaying.toggle() }
        case .play:
            action = "e.play();"
            optimistic { $0.isPlaying = true }
        case .pause:
            action = "e.pause();"
            optimistic { $0.isPlaying = false }
        case .next:
            action = "var b=document.querySelector('.ytp-next-button');if(b){b.click();}else if(isFinite(e.duration)){e.currentTime=e.duration;}"
        case .previous:
            action = "e.currentTime=0;"
            optimistic { $0.elapsed = 0 }
        case .seek(let position):
            action = "e.currentTime=\(position);"
            optimistic { $0.elapsed = position }
        case .setShuffle, .setRepeat, .setLiked:
            return
        }
        let js = Self.findElement + "(function(){var e=__notchMedia();if(!e)return '';\(action)return 'ok';})()"
        Task {
            _ = await AppleScriptRunner.string(browser.script(running: js))
            refreshSoon(0.5)
        }
    }
}
