import CoreAudio
import Foundation

/// Reports whether any input device is capturing, from CoreAudio property notifications.
@MainActor
final class MicrophoneMonitor {
    var onChange: (() -> Void)?
    private(set) var isActive = false

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    /// The app's own process tap shows up as a private aggregate device with input streams.
    private static let ownDevicePrefix = "Pro Notch"

    private var deviceListListener: AudioPropertyListener?
    private var deviceListeners: [AudioObjectID: AudioPropertyListener] = [:]
    private var processListListener: AudioPropertyListener?
    private var processes: [AudioObjectID] = []
    private var processListeners: [AudioObjectID: AudioPropertyListener] = [:]

    func start() {
        guard deviceListListener == nil else { return }
        deviceListListener = AudioPropertyListener(object: Self.system, selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.syncDevices()
        }
        syncDevices()
    }

    func stop() {
        deviceListListener?.remove()
        deviceListListener = nil
        deviceListeners.values.forEach { $0.remove() }
        deviceListeners = [:]
        untrackProcesses()
        isActive = false
    }

    private func syncDevices() {
        let inputs = Set(AudioQuery.objects(Self.system, kAudioHardwarePropertyDevices).filter(Self.isWatchedInput))
        for (id, listener) in deviceListeners where !inputs.contains(id) {
            listener.remove()
            deviceListeners[id] = nil
        }
        for id in inputs where deviceListeners[id] == nil {
            deviceListeners[id] = AudioPropertyListener(object: id, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in
                self?.evaluate()
            }
        }
        evaluate()
    }

    private static func isWatchedInput(_ device: AudioObjectID) -> Bool {
        guard AudioQuery.dataSize(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput) > 0 else { return false }
        return !(AudioQuery.string(device, kAudioObjectPropertyName)?.hasPrefix(ownDevicePrefix) ?? false)
    }

    private func evaluate() {
        let deviceRunning = deviceListeners.keys.contains { AudioQuery.uint32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0 != 0 }
        if deviceRunning { trackProcesses() } else { untrackProcesses() }

        // A device with both input and output streams also runs for playback, so confirm a process is actually capturing.
        let active = deviceRunning && (processListListener == nil || processes.contains(where: Self.isForeignCapture))
        guard active != isActive else { return }
        isActive = active
        onChange?()
    }

    private static func isForeignCapture(_ process: AudioObjectID) -> Bool {
        guard AudioQuery.uint32(process, kAudioProcessPropertyIsRunningInput) ?? 0 != 0 else { return false }
        return AudioQuery.pid(process) != getpid()
    }

    private func trackProcesses() {
        guard processListListener == nil else { return }
        processListListener = AudioPropertyListener(object: Self.system, selector: kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.syncProcesses()
            self?.evaluate()
        }
        if processListListener != nil { syncProcesses() }
    }

    private func untrackProcesses() {
        processListListener?.remove()
        processListListener = nil
        processListeners.values.forEach { $0.remove() }
        processListeners = [:]
        processes = []
    }

    private func syncProcesses() {
        processes = AudioQuery.objects(Self.system, kAudioHardwarePropertyProcessObjectList)
        let current = Set(processes)
        for (id, listener) in processListeners where !current.contains(id) {
            listener.remove()
            processListeners[id] = nil
        }
        for id in processes where processListeners[id] == nil {
            processListeners[id] = AudioPropertyListener(object: id, selector: kAudioProcessPropertyIsRunningInput) { [weak self] in
                self?.evaluate()
            }
        }
    }
}

/// A CoreAudio property listener delivered on the main queue. Keeps the block so removal matches registration.
final class AudioPropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        var address = AudioQuery.address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        guard AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        self.object = object
        self.address = address
        self.block = block
    }

    func remove() {
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}

enum AudioQuery {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func dataSize(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32 {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size = dataSize(object, selector)
        let stride = MemoryLayout<AudioObjectID>.stride
        guard size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / stride))
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func pid(_ process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
