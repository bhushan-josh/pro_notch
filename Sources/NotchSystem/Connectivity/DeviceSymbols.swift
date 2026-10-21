import AppKit
import IOBluetooth

struct DeviceAppearance: Equatable {
    var symbol: String
    /// Two buds plus a case, so left/right/case battery levels make sense.
    var isEarbuds: Bool
    var caseSymbol: String?
    var leftSymbol: String?
    var rightSymbol: String?
}

enum DeviceSymbols {
    static let fallback = "dot.radiowaves.left.and.right"

    @MainActor
    static func appearance(for device: IOBluetoothDevice) -> DeviceAppearance {
        let name = (device.name ?? "").lowercased()
        let appearance = fromName(name)
            ?? fromProductID(productID(of: device))
            ?? fromClass(major: device.deviceClassMajor, minor: device.deviceClassMinor)
            ?? DeviceAppearance(symbol: fallback, isEarbuds: false)
        guard NSImage(systemSymbolName: appearance.symbol, accessibilityDescription: nil) != nil else {
            return DeviceAppearance(symbol: fallback, isEarbuds: appearance.isEarbuds)
        }
        return appearance
    }

    private static let airpods = DeviceAppearance(
        symbol: "airpods", isEarbuds: true,
        caseSymbol: "airpods.chargingcase.fill", leftSymbol: "airpod.left", rightSymbol: "airpod.right"
    )
    private static let airpodsGen3 = DeviceAppearance(
        symbol: "airpods.gen3", isEarbuds: true,
        caseSymbol: "airpods.gen3.chargingcase.wireless.fill", leftSymbol: "airpod.gen3.left", rightSymbol: "airpod.gen3.right"
    )
    private static let airpodsGen4 = DeviceAppearance(
        symbol: "airpods.gen4", isEarbuds: true,
        caseSymbol: "airpods.gen4.chargingcase.wireless.fill", leftSymbol: "airpod.gen3.left", rightSymbol: "airpod.gen3.right"
    )
    private static let airpodsPro = DeviceAppearance(
        symbol: "airpodspro", isEarbuds: true,
        caseSymbol: "airpodspro.chargingcase.wireless.fill", leftSymbol: "airpodpro.left", rightSymbol: "airpodpro.right"
    )
    private static let airpodsMax = DeviceAppearance(symbol: "airpodsmax", isEarbuds: false)

    private static func buds(_ symbol: String) -> DeviceAppearance {
        DeviceAppearance(symbol: symbol, isEarbuds: true, caseSymbol: "capsule.fill")
    }

    private static func plain(_ symbol: String) -> DeviceAppearance {
        DeviceAppearance(symbol: symbol, isEarbuds: false)
    }

    private static func fromName(_ name: String) -> DeviceAppearance? {
        func has(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }

        if has("airpods max") { return airpodsMax }
        if has("airpods pro") { return airpodsPro }
        if has("airpods") {
            if has("(4", "4th", "airpods 4") { return airpodsGen4 }
            if has("(3", "3rd", "airpods 3") { return airpodsGen3 }
            return airpods
        }
        if has("powerbeats pro") { return buds("beats.powerbeatspro") }
        if has("powerbeats") { return plain("beats.powerbeats") }
        if has("studio buds") { return buds("beats.studiobuds") }
        if has("solo buds") { return buds("beats.solobuds") }
        if has("beats fit") { return buds("beats.fitpro") }
        if has("beats flex", "beatsx") { return plain("beats.earphones") }
        if has("beats pill") { return plain("beats.pill") }
        if has("beats") { return plain("beats.headphones") }
        if has("trackpad") { return plain("rectangle.and.hand.point.up.left.fill") }
        if has("magic mouse") { return plain("magicmouse.fill") }
        if has("mouse", "mx master", "mx anywhere") { return plain("computermouse.fill") }
        if has("keyboard", "keys") { return plain("keyboard.fill") }
        if has("controller", "dualsense", "dualshock", "xbox", "joy-con", "gamepad", "8bitdo") { return plain("gamecontroller.fill") }
        if has("watch") { return plain("applewatch") }
        if has("iphone") { return plain("iphone") }
        if has("ipad") { return plain("ipad") }
        if has("macbook") { return plain("laptopcomputer") }
        if has("homepod") { return plain("homepod.fill") }
        if has("buds", "earbuds", "wf-", "galaxy buds", "pixel buds") { return buds("earbuds") }
        if has("speaker", "soundlink", "jbl", "boom", "sonos", "soundcore", "marshall") { return plain("hifispeaker.fill") }
        if has("headphone", "headset", "wh-", "bose", "sennheiser") { return plain("headphones") }
        return nil
    }

    /// Apple's private `productID` accessor, when this IOBluetooth build has it. Only trusted for Apple's vendor ID.
    @MainActor
    private static func productID(of device: IOBluetoothDevice) -> Int? {
        func number(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            return (device.value(forKey: key) as? NSNumber)?.intValue
        }
        if let vendor = number("vendorID"), vendor != 0x004C { return nil }
        return number("productID")
    }

    private static func fromProductID(_ id: Int?) -> DeviceAppearance? {
        switch id {
        case 0x2002, 0x200F: airpods
        case 0x2013: airpodsGen3
        case 0x2019, 0x201B: airpodsGen4
        case 0x200E, 0x2014, 0x2024, 0x2027: airpodsPro
        case 0x200A, 0x201F: airpodsMax
        default: nil
        }
    }

    private static func fromClass(major: BluetoothDeviceClassMajor, minor: BluetoothDeviceClassMinor) -> DeviceAppearance? {
        switch major {
        case 0x01: return plain("laptopcomputer")
        case 0x02: return plain("iphone")
        case 0x04:
            switch minor {
            case 0x01, 0x02, 0x06: return plain("headphones")
            case 0x05, 0x07, 0x0A: return plain("hifispeaker.fill")
            case 0x08: return plain("car.fill")
            case 0x12: return plain("gamecontroller.fill")
            default: return plain("headphones")
            }
        case 0x05:
            if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return plain("gamecontroller.fill") }
            if minor & 0x10 != 0 { return plain("keyboard.fill") }
            if minor & 0x20 != 0 { return plain("computermouse.fill") }
            return nil
        case 0x07: return minor == 0x01 ? plain("applewatch") : nil
        case 0x08: return plain("gamecontroller.fill")
        default: return nil
        }
    }
}
