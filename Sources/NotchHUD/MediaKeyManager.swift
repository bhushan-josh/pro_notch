import AppKit
import ApplicationServices
import NotchCore

enum MediaKey: Int, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case illuminationUp = 21
    case illuminationDown = 22
    case illuminationToggle = 23
}

struct MediaKeyEvent: Sendable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    let shift: Bool
    let option: Bool

    var isFine: Bool { shift && option }
}

/// Watches hardware media keys with a session event tap so the system OSD can be replaced.
@MainActor
final class MediaKeyManager {
    /// Return true to swallow the event so the system never sees it.
    var handler: ((MediaKeyEvent) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    nonisolated static let systemDefinedType = CGEventType(rawValue: 14)!
    nonisolated private static let auxControlSubtype: Int16 = 8

    var isInstalled: Bool { tap != nil }

    func start() {
        install()
        timer?.invalidate()
        // Accessibility can be granted at any time; keep retrying, and revive the tap if the system disabled it.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintain() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        uninstall()
    }

    private func maintain() {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        } else {
            install()
        }
    }

    private func install() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = runLoopSource
    }

    private func uninstall() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(_ event: MediaKeyEvent) -> Bool {
        handler?(event) ?? false
    }

    nonisolated static func decode(_ event: CGEvent) -> MediaKeyEvent? {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == auxControlSubtype else { return nil }
        let data = nsEvent.data1
        let code = (data & 0xFFFF_0000) >> 16
        guard let key = MediaKey(rawValue: code) else { return nil }
        let flags = nsEvent.modifierFlags
        return MediaKeyEvent(
            key: key,
            isDown: ((data & 0xFF00) >> 8) == 0xA,
            isRepeat: (data & 0x1) == 1,
            shift: flags.contains(.shift),
            option: flags.contains(.option)
        )
    }

    // MARK: Accessibility

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        Defaults[HUDSettings.accessibilityRequested] = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static let permission = PermissionRequirement(
        id: "accessibility",
        title: "Accessibility",
        description: "Lets Dynamic Notch intercept the volume and brightness keys and replace the system HUD.",
        symbol: "accessibility",
        settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
        status: {
            if AXIsProcessTrusted() { return .granted }
            return Defaults[HUDSettings.accessibilityRequested] ? .denied : .notDetermined
        },
        request: { MediaKeyManager.requestTrust() }
    )
}

/// The tap's run loop source lives on the main run loop, so callbacks arrive on the main thread.
private let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<MediaKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { manager.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type == MediaKeyManager.systemDefinedType, let decoded = MediaKeyManager.decode(event) else {
        return Unmanaged.passUnretained(event)
    }
    let consume = MainActor.assumeIsolated { manager.handle(decoded) }
    return consume ? nil : Unmanaged.passUnretained(event)
}
