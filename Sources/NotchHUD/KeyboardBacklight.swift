import Foundation
import ObjectiveC
import Observation

/// Keyboard backlight level through CoreBrightness's `KeyboardBrightnessClient`. Unavailable on Macs without one.
@MainActor
@Observable
public final class KeyboardBacklight {
    public private(set) var level: Double = 0
    public private(set) var isAvailable = false

    private typealias GetLevel = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetLevel = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?

    @ObservationIgnored private var client: NSObject?
    @ObservationIgnored private var keyboardID: UInt64 = 1
    @ObservationIgnored private var getLevel: GetLevel?
    @ObservationIgnored private var setLevel: SetLevel?
    @ObservationIgnored private var restoreLevel: Double = 0.5

    private static let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
    private static let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

    public init() {}

    func start() {
        guard client == nil else { return }
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }
        let instance = type.init()
        guard instance.responds(to: Self.getSelector), instance.responds(to: Self.setSelector) else { return }
        client = instance
        getLevel = unsafeBitCast(instance.method(for: Self.getSelector), to: GetLevel.self)
        setLevel = unsafeBitCast(instance.method(for: Self.setSelector), to: SetLevel.self)
        if instance.responds(to: Self.idsSelector) {
            let copyIDs = unsafeBitCast(instance.method(for: Self.idsSelector), to: CopyIDs.self)
            let ids = copyIDs(instance, Self.idsSelector)?.takeRetainedValue() as? [NSNumber] ?? []
            guard let first = ids.first else { return }
            keyboardID = first.uint64Value
        }
        isAvailable = true
        refresh()
    }

    @discardableResult
    func refresh() -> Double? {
        guard let client, let getLevel else { return nil }
        let value = Double(min(max(getLevel(client, Self.getSelector, keyboardID), 0), 1))
        level = value
        return value
    }

    public func setLevel(_ value: Double) {
        guard let client, let setLevel else { return }
        let value = min(max(value, 0), 1)
        if setLevel(client, Self.setSelector, Float(value), keyboardID) {
            level = value
        }
    }

    func toggle() {
        if level > 0.001 {
            restoreLevel = level
            setLevel(0)
        } else {
            setLevel(restoreLevel > 0.001 ? restoreLevel : 0.5)
        }
    }
}
