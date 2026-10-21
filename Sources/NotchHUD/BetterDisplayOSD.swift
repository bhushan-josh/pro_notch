import Foundation

/// Mirrors BetterDisplay's OSD broadcasts (external display brightness and DDC volume) into the notch HUD.
///
/// The payload is undocumented, so every field is optional and anything unrecognised is ignored.
@MainActor
final class BetterDisplayOSD {
    enum Kind { case brightness, volume }

    struct Level {
        var kind: Kind
        var value: Double
        var muted: Bool
    }

    var onLevel: ((Level) -> Void)?

    private var observer: NSObjectProtocol?
    private static let name = Notification.Name("com.betterdisplay.BetterDisplay.osd")

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.name, object: nil, queue: .main
        ) { [weak self] note in
            let payload = Self.payload(of: note)
            MainActor.assumeIsolated {
                guard let self, let level = Self.parse(payload) else { return }
                self.onLevel?(level)
            }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
    }

    nonisolated private static func payload(of note: Notification) -> [String: String] {
        var raw: [String: Any] = [:]
        if let object = note.object as? String,
           let data = object.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            raw.merge(json) { current, _ in current }
        }
        if let info = note.userInfo {
            for (key, value) in info {
                if let key = key as? String { raw[key] = value }
            }
        }
        var flat: [String: String] = [:]
        for (key, value) in raw {
            switch value {
            case let number as NSNumber: flat[key.lowercased()] = number.stringValue
            case let string as String: flat[key.lowercased()] = string
            default: continue
            }
        }
        return flat
    }

    nonisolated private static func parse(_ payload: [String: String]) -> Level? {
        let valueKeys = ["value", "level", "brightness", "volume"]
        guard let value = valueKeys.lazy.compactMap({ payload[$0].flatMap(Double.init) }).first else { return nil }
        let maximum = ["maxvalue", "max"].lazy.compactMap { payload[$0].flatMap(Double.init) }.first ?? (value > 1 ? 100 : 1)
        guard maximum > 0 else { return nil }
        let normalized = value / maximum
        guard normalized.isFinite, (-0.001...1.001).contains(normalized) else { return nil }

        let descriptor = ["controltarget", "target", "type", "control", "symbol", "customsymbol", "icon"]
            .compactMap { payload[$0]?.lowercased() }
            .joined(separator: " ")
        let iconID = payload["systemiconid"].flatMap(Int.init)
        let muted = descriptor.contains("mute") || iconID == 4

        let kind: Kind
        if ["volume", "audio", "speaker", "mute"].contains(where: descriptor.contains) || iconID == 3 || iconID == 4 {
            kind = .volume
        } else if ["bright", "backlight", "sun", "dimming"].contains(where: descriptor.contains) || iconID == 1 {
            kind = .brightness
        } else {
            return nil
        }
        return Level(kind: kind, value: min(max(normalized, 0), 1), muted: muted)
    }
}
