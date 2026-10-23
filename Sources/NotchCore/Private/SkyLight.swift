import AppKit

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSpaceCreate")
private func CGSSpaceCreate(_ cid: CGSConnectionID, _ flag: Int32, _ options: CFDictionary?) -> CGSSpaceID

@_silgen_name("CGSSpaceDestroy")
private func CGSSpaceDestroy(_ cid: CGSConnectionID, _ space: CGSSpaceID)

@_silgen_name("CGSSpaceSetAbsoluteLevel")
private func CGSSpaceSetAbsoluteLevel(_ cid: CGSConnectionID, _ space: CGSSpaceID, _ level: Int32)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: CFArray, _ spaces: CFArray)

@_silgen_name("CGSShowSpaces")
private func CGSShowSpaces(_ cid: CGSConnectionID, _ spaces: CFArray)

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>?

/// A private window-server space pinned above everything, including the lock screen and fullscreen apps.
///
/// Windows added here stay visible while the session is locked, which is how notch apps draw over the lock screen.
@MainActor
public final class OverlaySpace {
    public static let shared = OverlaySpace()

    /// Above the lock screen shield. Lower values (e.g. 100) sit under it.
    private static let absoluteLevel: Int32 = 400

    private let connection = CGSMainConnectionID()
    private let space: CGSSpaceID
    private var windowNumbers = Set<Int>()

    private init() {
        space = CGSSpaceCreate(connection, 1, nil)
        CGSSpaceSetAbsoluteLevel(connection, space, Self.absoluteLevel)
        CGSShowSpaces(connection, [NSNumber(value: space)] as CFArray)
    }

    public func add(_ window: NSWindow) {
        let number = window.windowNumber
        guard number > 0, windowNumbers.insert(number).inserted else { return }
        CGSAddWindowsToSpaces(connection, [NSNumber(value: number)] as CFArray, [NSNumber(value: space)] as CFArray)
    }

    public func remove(_ window: NSWindow) {
        let number = window.windowNumber
        guard windowNumbers.remove(number) != nil else { return }
        CGSRemoveWindowsFromSpaces(connection, [NSNumber(value: number)] as CFArray, [NSNumber(value: space)] as CFArray)
    }
}

public enum SpaceInspector {
    private static let fullscreenSpaceType = 4

    /// Display UUIDs whose current space is a fullscreen app space.
    public static func fullscreenDisplayUUIDs() -> Set<String> {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        var result = Set<String>()
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let type = current["type"] as? Int, type == fullscreenSpaceType,
                  var identifier = display["Display Identifier"] as? String
            else { continue }
            // With "Displays have separate Spaces" off, the only entry is named "Main".
            if identifier == "Main", let main = NSScreen.screens.first { identifier = main.displayUUID }
            result.insert(identifier)
        }
        return result
    }
}

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var displayUUID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    var hasPhysicalNotch: Bool { safeAreaInsets.top > 0 }
}
