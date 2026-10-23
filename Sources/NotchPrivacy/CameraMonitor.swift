import CoreMediaIO
import Foundation

/// Reports whether any video capture device is running in some process, from CoreMediaIO property notifications.
@MainActor
final class CameraMonitor {
    var onChange: (() -> Void)?
    private(set) var isActive = false

    private static let system = CMIOObjectID(kCMIOObjectSystemObject)

    private var deviceListListener: CMIOPropertyListener?
    private var deviceListeners: [CMIOObjectID: CMIOPropertyListener] = [:]

    func start() {
        guard deviceListListener == nil else { return }
        deviceListListener = CMIOPropertyListener(object: Self.system, selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)) { [weak self] in
            self?.syncDevices()
        }
        syncDevices()
    }

    func stop() {
        deviceListListener?.remove()
        deviceListListener = nil
        deviceListeners.values.forEach { $0.remove() }
        deviceListeners = [:]
        isActive = false
    }

    private func syncDevices() {
        let devices = Set(CMIOQuery.objects(Self.system, CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)).filter(Self.hasVideoInput))
        for (id, listener) in deviceListeners where !devices.contains(id) {
            listener.remove()
            deviceListeners[id] = nil
        }
        for id in devices where deviceListeners[id] == nil {
            deviceListeners[id] = CMIOPropertyListener(object: id, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                self?.evaluate()
            }
        }
        evaluate()
    }

    private static func hasVideoInput(_ device: CMIOObjectID) -> Bool {
        CMIOQuery.dataSize(device, CMIOObjectPropertySelector(kCMIODevicePropertyStreams), scope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput)) > 0
    }

    private func evaluate() {
        let active = deviceListeners.keys.contains {
            CMIOQuery.uint32($0, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) ?? 0 != 0
        }
        guard active != isActive else { return }
        isActive = active
        onChange?()
    }
}

/// A CoreMediaIO property listener delivered on the main queue. Keeps the block so removal matches registration.
final class CMIOPropertyListener {
    private let object: CMIOObjectID
    private var address: CMIOObjectPropertyAddress
    private let block: CMIOObjectPropertyListenerBlock

    init?(object: CMIOObjectID, selector: CMIOObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
        var address = CMIOQuery.address(selector)
        guard CMIOObjectHasProperty(object, &address) else { return nil }
        let block: CMIOObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        guard CMIOObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr else { return nil }
        self.object = object
        self.address = address
        self.block = block
    }

    func remove() {
        CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}

enum CMIOQuery {
    static func address(_ selector: CMIOObjectPropertySelector, scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    static func dataSize(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector, scope: CMIOObjectPropertyScope = CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal)) -> UInt32 {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return size
    }

    static func objects(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        var address = address(selector)
        let size = dataSize(object, selector)
        let stride = MemoryLayout<CMIOObjectID>.stride
        guard size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / stride)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / stride))
    }

    static func uint32(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr else { return nil }
        return value
    }
}
