import Foundation
import IOBluetooth
import IOKit

struct DeviceBattery: Equatable {
    var single: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool { single == nil && left == nil && right == nil && caseLevel == nil }
    var hasComponents: Bool { left != nil || right != nil }

    /// The level to show in the wing: the device itself, or the weaker bud.
    var primary: Int? {
        single ?? [left, right].compactMap { $0 }.min()
    }
}

enum BluetoothBattery {
    @MainActor
    static func read(_ device: IOBluetoothDevice) -> DeviceBattery {
        var battery = DeviceBattery(
            single: privateLevel(device, "batteryPercentSingle") ?? privateLevel(device, "batteryPercentCombined"),
            left: privateLevel(device, "batteryPercentLeft"),
            right: privateLevel(device, "batteryPercentRight"),
            caseLevel: privateLevel(device, "batteryPercentCase")
        )
        if battery.isEmpty, let level = hidLevel(address: device.addressString, name: device.name) {
            battery.single = level
        }
        return battery
    }

    /// Private IOBluetoothDevice accessors that AirPods and Beats populate. 0 means unknown.
    @MainActor
    private static func privateLevel(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        guard device.responds(to: NSSelectorFromString(key)),
              let value = (device.value(forKey: key) as? NSNumber)?.intValue,
              (1...100).contains(value)
        else { return nil }
        return value
    }

    /// Magic Keyboard, Mouse and Trackpad publish their level on a HID service in the IORegistry.
    static func hidLevel(address: String?, name: String?) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let wantedAddress = address.map(normalize)
        var nameMatch: Int?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let level = property(service, "BatteryPercent") as? Int, (0...100).contains(level) else { continue }
            if let wantedAddress, let deviceAddress = property(service, "DeviceAddress") as? String,
               normalize(deviceAddress) == wantedAddress {
                return level
            }
            if let name, let product = property(service, "Product") as? String, product == name {
                nameMatch = level
            }
        }
        return nameMatch
    }

    private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: ":", with: "-")
    }
}
