import AppKit

/// Runs AppleScript off the main thread. NSAppleScript is not thread-safe, so every script goes through one serial queue.
public enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "notch.applescript", qos: .userInitiated)

    public struct ScriptError: Error, CustomStringConvertible {
        public let info: [String: Any]
        public var description: String { (info[NSAppleScript.errorMessage] as? String) ?? "AppleScript error" }
        public var code: Int { info[NSAppleScript.errorNumber] as? Int ?? 0 }
    }

    @discardableResult
    public static func run(_ source: String) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: ScriptError(info: (error as? [String: Any]) ?? [:]))
                }
            }
        }
    }

    /// Returns nil instead of throwing; for polling where failures are expected (app not running, no permission).
    public static func string(_ source: String) async -> String? {
        try? await run(source).stringValue
    }

    public static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
