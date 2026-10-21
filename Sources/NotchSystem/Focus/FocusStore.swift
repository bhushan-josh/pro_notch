import AppKit
import NotchCore

struct FocusModeConfig: Sendable, Equatable {
    var name: String?
    var symbol: String?
    var tint: String?
}

struct FocusReading: Sendable, Equatable {
    var activeIdentifier: String?
    var configs: [String: FocusModeConfig]
}

/// Reads the Focus database the system keeps in ~/Library/DoNotDisturb. It is TCC protected (Full Disk Access).
enum FocusStore {
    static let directory: URL = {
        // The real home even if the app is ever sandboxed, since the database lives outside any container.
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }()
    static let assertionsURL = directory.appendingPathComponent("Assertions.json")
    static let configurationsURL = directory.appendingPathComponent("ModeConfigurations.json")

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    @MainActor
    static var requirement: PermissionRequirement {
        PermissionRequirement(
            id: "fullDiskAccess",
            title: "Full Disk Access",
            description: "Read which Focus is active so the notch can show it and quiet other activities.",
            symbol: "moon.fill",
            settingsURL: settingsURL,
            status: { canRead ? .granted : .notDetermined },
            request: { if let settingsURL { NSWorkspace.shared.open(settingsURL) } }
        )
    }

    /// TCC denials surface as EPERM on listing the directory; a missing directory has nothing to protect.
    static var canRead: Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    /// Nil when the database cannot be read, which is different from "no Focus active".
    static func read() -> FocusReading? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let stores = root["data"] as? [[String: Any]] ?? []
        let records = stores.first?["storeAssertionRecords"] as? [[String: Any]] ?? []
        let active = records
            .sorted { timestamp($0) < timestamp($1) }
            .compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }
            .last
        return FocusReading(activeIdentifier: active, configs: readConfigurations())
    }

    private static func timestamp(_ record: [String: Any]) -> Double {
        (record["assertionStartDateTimestamp"] as? NSNumber)?.doubleValue ?? 0
    }

    private static func readConfigurations() -> [String: FocusModeConfig] {
        guard let data = try? Data(contentsOf: configurationsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]],
              let modes = stores.first?["modeConfigurations"] as? [String: Any]
        else { return [:] }

        var result: [String: FocusModeConfig] = [:]
        for (identifier, value) in modes {
            guard let mode = (value as? [String: Any])?["mode"] as? [String: Any] else { continue }
            result[mode["modeIdentifier"] as? String ?? identifier] = FocusModeConfig(
                name: mode["name"] as? String,
                symbol: mode["symbolImageName"] as? String,
                tint: mode["tintColorName"] as? String
            )
        }
        return result
    }
}
