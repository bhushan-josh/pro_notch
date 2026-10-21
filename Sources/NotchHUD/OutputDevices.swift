import AppKit
import CoreAudio
import Observation
import NotchCore

enum AudioProperty {
    static func address(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func exists(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return object != kAudioObjectUnknown && AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        guard exists(object, address) else { return false }
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func value<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        guard exists(object, address) else { return nil }
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    @discardableResult
    static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ newValue: T) -> Bool {
        guard isSettable(object, address) else { return false }
        var address = address
        var value = newValue
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &value) { AudioObjectSetPropertyData(object, &address, 0, nil, size, $0) } == noErr
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        guard exists(object, address) else { return nil }
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objectIDs(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> [AudioObjectID] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = MemoryLayout<AudioObjectID>.stride
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / stride)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / stride))
    }

    static func dataSize(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32 {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return 0 }
        return size
    }
}

/// A CoreAudio property listener delivered on the main queue. Keeps the block so removal matches registration.
final class AudioListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init?(object: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping @MainActor () -> Void) {
        guard AudioProperty.exists(object, address) else { return nil }
        self.object = object
        self.address = address
        block = { _, _ in MainActor.assumeIsolated { handler() } }
        var registered = address
        guard AudioObjectAddPropertyListenerBlock(object, &registered, .main, block) == noErr else { return nil }
    }

    func remove() {
        AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
}

public enum AudioOutputKind: Sendable {
    case builtInSpeakers, builtInHeadphones, airpods, airpodsPro, airpodsMax, beats
    case headphones, bluetoothSpeaker, airplay, hdmi, display, usb, virtual, aggregate, other

    /// Personal listening devices get their own symbol in the volume HUD instead of a speaker.
    var isPersonal: Bool {
        switch self {
        case .builtInHeadphones, .airpods, .airpodsPro, .airpodsMax, .beats, .headphones: true
        default: false
        }
    }
}

public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let transportType: UInt32
    public let kind: AudioOutputKind

    public var isBuiltInSpeakers: Bool { kind == .builtInSpeakers }

    public var symbol: String {
        let preferred: String = switch kind {
        case .builtInSpeakers:
            name.localizedCaseInsensitiveContains("MacBook") ? "laptopcomputer"
                : name.localizedCaseInsensitiveContains("iMac") ? "desktopcomputer" : "speaker.wave.2.fill"
        case .builtInHeadphones, .headphones: "headphones"
        case .airpods: "airpods"
        case .airpodsPro: "airpodspro"
        case .airpodsMax: "airpodsmax"
        case .beats: "beats.headphones"
        case .bluetoothSpeaker: "hifispeaker.fill"
        case .airplay: "airplayaudio"
        case .hdmi: "tv"
        case .display: "display"
        case .usb: "hifispeaker.fill"
        case .virtual: "waveform"
        case .aggregate: "rectangle.stack.fill"
        case .other: "speaker.wave.2.fill"
        }
        return SymbolCheck.resolve(preferred, fallback: kind.isPersonal ? "headphones" : "speaker.wave.2.fill")
    }
}

enum SymbolCheck {
    static func resolve(_ name: String, fallback: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
    }
}

/// Output device list and the default output, with change callbacks.
@MainActor
@Observable
public final class OutputDevices {
    public private(set) var devices: [AudioOutputDevice] = []
    public private(set) var defaultDeviceID: AudioObjectID = kAudioObjectUnknown

    /// Fires when the default output device (or the built-in jack's data source) changes.
    @ObservationIgnored var onDefaultDeviceChange: ((AudioOutputDevice?) -> Void)?

    @ObservationIgnored private var listeners: [AudioListener] = []
    @ObservationIgnored private var dataSourceListener: AudioListener?
    @ObservationIgnored private var lastDefaultSignature: String?

    public var defaultDevice: AudioOutputDevice? {
        devices.first { $0.id == defaultDeviceID } ?? Self.makeDevice(defaultDeviceID)
    }

    public init() {}

    func start() {
        guard listeners.isEmpty else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        listeners = [
            AudioListener(object: system, address: AudioProperty.address(kAudioHardwarePropertyDevices)) { [weak self] in
                self?.reloadDevices()
            },
            AudioListener(object: system, address: AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
                self?.defaultChanged()
            },
        ].compactMap { $0 }
        reloadDevices()
        defaultDeviceID = Self.currentDefaultID()
        lastDefaultSignature = signature(of: defaultDevice)
        watchDataSource()
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners = []
        dataSourceListener?.remove()
        dataSourceListener = nil
    }

    public func setDefault(uid: String) {
        guard let device = devices.first(where: { $0.uid == uid }) else { return }
        setDefault(device)
    }

    public func setDefault(_ device: AudioOutputDevice) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let systemOutput = AudioProperty.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let previous = defaultDeviceID
        let alertsFollowed = AudioProperty.value(system, systemOutput, initial: AudioObjectID(0)) == previous
        AudioProperty.set(system, AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice), device.id)
        if alertsFollowed {
            AudioProperty.set(system, systemOutput, device.id)
        }
    }

    private func reloadDevices() {
        let ids = AudioProperty.objectIDs(AudioObjectID(kAudioObjectSystemObject), AudioProperty.address(kAudioHardwarePropertyDevices))
        devices = ids.compactMap(Self.makeDevice).sorted { lhs, rhs in
            if lhs.isBuiltInSpeakers != rhs.isBuiltInSpeakers { return lhs.isBuiltInSpeakers }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func defaultChanged() {
        defaultDeviceID = Self.currentDefaultID()
        reloadDevices()
        watchDataSource()
        notifyIfChanged()
    }

    private func notifyIfChanged() {
        let device = defaultDevice
        let signature = signature(of: device)
        guard signature != lastDefaultSignature else { return }
        lastDefaultSignature = signature
        onDefaultDeviceChange?(device)
    }

    private func signature(of device: AudioOutputDevice?) -> String {
        guard let device else { return "" }
        return "\(device.uid)|\(device.kind)"
    }

    /// Intel Macs report headphones in the built-in jack as a data source change rather than a new device.
    private func watchDataSource() {
        dataSourceListener?.remove()
        dataSourceListener = AudioListener(
            object: defaultDeviceID,
            address: AudioProperty.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput)
        ) { [weak self] in
            self?.reloadDevices()
            self?.notifyIfChanged()
        }
    }

    static func currentDefaultID() -> AudioObjectID {
        AudioProperty.value(
            AudioObjectID(kAudioObjectSystemObject),
            AudioProperty.address(kAudioHardwarePropertyDefaultOutputDevice),
            initial: AudioObjectID(kAudioObjectUnknown)
        ) ?? kAudioObjectUnknown
    }

    static func makeDevice(_ id: AudioObjectID) -> AudioOutputDevice? {
        guard id != kAudioObjectUnknown else { return nil }
        let streams = AudioProperty.dataSize(id, AudioProperty.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput))
        guard streams > 0 else { return nil }
        guard let uid = AudioProperty.string(id, AudioProperty.address(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = AudioProperty.string(id, AudioProperty.address(kAudioObjectPropertyName)) ?? "Output"
        let transport = AudioProperty.value(id, AudioProperty.address(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0
        let dataSource = AudioProperty.value(
            id, AudioProperty.address(kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput), initial: UInt32(0)
        )
        return AudioOutputDevice(
            id: id, uid: uid, name: name, transportType: transport,
            kind: kind(name: name, transport: transport, dataSource: dataSource)
        )
    }

    private static let headphonesDataSource: UInt32 = 0x6864_706E // 'hdpn'

    private static func kind(name: String, transport: UInt32, dataSource: UInt32?) -> AudioOutputKind {
        let lower = name.lowercased()
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            if dataSource == headphonesDataSource || lower.contains("headphone") { return .builtInHeadphones }
            return .builtInSpeakers
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if lower.contains("airpods max") { return .airpodsMax }
            if lower.contains("airpods pro") { return .airpodsPro }
            if lower.contains("airpods") { return .airpods }
            if lower.contains("beats") { return .beats }
            let speakerHints = ["speaker", "homepod", "boom", "jbl", "soundlink", "sonos", "flip", "charge"]
            if speakerHints.contains(where: lower.contains) { return .bluetoothSpeaker }
            return .headphones
        case kAudioDeviceTransportTypeAirPlay:
            return .airplay
        case kAudioDeviceTransportTypeHDMI:
            return .hdmi
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeThunderbolt:
            return .display
        case kAudioDeviceTransportTypeUSB:
            return lower.contains("headphone") || lower.contains("headset") ? .headphones : .usb
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            return .aggregate
        default:
            return .other
        }
    }
}
