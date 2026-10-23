import AppKit
import CoreGraphics
import Observation

/// Display brightness through the private DisplayServices framework, which covers built-in panels and Apple displays.
@MainActor
@Observable
public final class BrightnessManager {
    public private(set) var brightness: Double = 0
    public private(set) var isAvailable = false

    /// Reports a brightness change from outside this manager. `userDriven` is false for what looks like ambient drift.
    @ObservationIgnored var onExternalChange: ((_ value: Double, _ userDriven: Bool) -> Void)?

    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeFunction = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias RegisterFunction = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32
    private typealias UnregisterFunction = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32

    private struct Functions {
        var get: GetFunction
        var set: SetFunction
        var canChange: CanChangeFunction?
        var register: RegisterFunction?
        var unregister: UnregisterFunction?
    }

    @ObservationIgnored private let functions: Functions?
    @ObservationIgnored private var displayID: CGDirectDisplayID = 0
    @ObservationIgnored private var registeredDisplay: CGDirectDisplayID?
    @ObservationIgnored private var ownChangeUntil = Date.distantPast
    @ObservationIgnored private var lastUserIntent = Date.distantPast
    @ObservationIgnored private var samples: [(time: Date, value: Double)] = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var rampTask: Task<Void, Never>?
    @ObservationIgnored private var lastApplied: Double = 0

    @ObservationIgnored fileprivate static weak var active: BrightnessManager?

    public init() {
        functions = Self.loadFunctions()
    }

    func start() {
        Self.active = self
        selectDisplay()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectDisplay() }
        }
    }

    func stop() {
        rampTask?.cancel()
        rampTask = nil
        unregister()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if Self.active === self { Self.active = nil }
    }

    /// A brightness key went by that this app did not handle itself, so the next change is the user's.
    func noteUserIntent() {
        lastUserIntent = Date()
    }

    /// DisplayServicesSetBrightnessSmooth reports success but leaves the panel unchanged on macOS 27,
    /// so the ramp is done here with the plain setter.
    public func setBrightness(_ value: Double) {
        guard let functions, isAvailable else { return }
        let target = min(max(value, 0), 1)
        let start = rampTask != nil ? lastApplied : (read() ?? brightness)
        brightness = target
        rampTask?.cancel()
        rampTask = nil
        ownChangeUntil = Date().addingTimeInterval(0.5)
        guard abs(target - start) > 0.001 else {
            apply(target, with: functions)
            return
        }
        let steps = 6
        rampTask = Task { [weak self] in
            for step in 1...steps {
                guard let self, !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 2)
                self.apply(start + (target - start) * eased, with: functions)
                if step < steps { try? await Task.sleep(for: .milliseconds(16)) }
            }
            self?.rampTask = nil
        }
    }

    private func apply(_ value: Double, with functions: Functions) {
        _ = functions.set(displayID, Float(value))
        lastApplied = value
    }

    func read() -> Double? {
        guard let functions, displayID != 0 else { return nil }
        var value: Float = 0
        guard functions.get(displayID, &value) == 0 else { return nil }
        return Double(min(max(value, 0), 1))
    }

    private func selectDisplay() {
        guard let functions else { return }
        let target = Self.builtInDisplayID() ?? CGMainDisplayID()
        let canChange = functions.canChange?(target) ?? true
        displayID = target
        let value = read()
        isAvailable = canChange && value != nil
        if let value { brightness = value }
        if isAvailable, registeredDisplay != target {
            unregister()
            if let register = functions.register, register(target, nil, brightnessChangeCallback) == 0 {
                registeredDisplay = target
            }
        } else if !isAvailable {
            unregister()
        }
    }

    private func unregister() {
        guard let display = registeredDisplay else { return }
        _ = functions?.unregister?(display, nil)
        registeredDisplay = nil
    }

    fileprivate func systemChanged() {
        let now = Date()
        if now < ownChangeUntil { return }
        guard let value = read() else { return }
        let previous = brightness
        brightness = value
        samples.append((now, value))
        samples.removeAll { now.timeIntervalSince($0.time) > 0.6 }
        guard abs(value - previous) >= 0.002 else { return }
        let values = samples.map(\.value)
        let span = (values.max() ?? value) - (values.min() ?? value)
        // Auto-brightness ramps slowly; keys and sliders move several percent within half a second.
        let userDriven = now.timeIntervalSince(lastUserIntent) < 1.2 || span >= 0.03 || abs(value - previous) >= 0.03
        onExternalChange?(value, userDriven)
    }

    private static func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsActive($0) != 0 }
    }

    private static func loadFunctions() -> Functions? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            return nil
        }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let get = symbol("DisplayServicesGetBrightness", as: GetFunction.self),
              let set = symbol("DisplayServicesSetBrightness", as: SetFunction.self)
        else { return nil }
        return Functions(
            get: get,
            set: set,
            canChange: symbol("DisplayServicesCanChangeBrightness", as: CanChangeFunction.self),
            register: symbol("DisplayServicesRegisterForBrightnessChangeNotifications", as: RegisterFunction.self),
            unregister: symbol("DisplayServicesUnregisterForBrightnessChangeNotifications", as: UnregisterFunction.self)
        )
    }
}

/// DisplayServices calls this on its own client queue.
private let brightnessChangeCallback: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async {
        MainActor.assumeIsolated { BrightnessManager.active?.systemChanged() }
    }
}
