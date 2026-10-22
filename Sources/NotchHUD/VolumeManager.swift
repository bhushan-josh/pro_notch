import AudioToolbox
import CoreAudio
import Foundation
import Observation

/// Volume and mute of the default output device, read and written through CoreAudio.
@MainActor
@Observable
public final class VolumeManager {
    public private(set) var deviceID: AudioObjectID = kAudioObjectUnknown
    public private(set) var volume: Double = 0
    public private(set) var isMuted = false
    /// False for outputs the system cannot attenuate (most HDMI and some USB devices).
    public private(set) var canSetVolume = false
    public private(set) var canMute = false

    /// Fires for changes that did not come from this manager's own setters, from any app or Control Center.
    @ObservationIgnored var onExternalChange: (() -> Void)?

    @ObservationIgnored private var listeners: [AudioListener] = []
    @ObservationIgnored private var boundAt = Date.distantPast
    @ObservationIgnored private var emulatedMuteRestore: Double?

    private static let channels: [AudioObjectPropertyElement] = [1, 2]
    private static let output = kAudioObjectPropertyScopeOutput

    public init() {}

    var effectiveVolume: Double { isMuted ? 0 : volume }

    func bind(to device: AudioObjectID) {
        unbind()
        deviceID = device
        boundAt = Date()
        emulatedMuteRestore = nil
        refresh()
        guard device != kAudioObjectUnknown else { return }
        var addresses = [
            AudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Self.output),
            AudioProperty.address(kAudioDevicePropertyVolumeScalar, Self.output),
            AudioProperty.address(kAudioDevicePropertyMute, Self.output),
        ]
        for channel in Self.channels {
            addresses.append(AudioProperty.address(kAudioDevicePropertyVolumeScalar, Self.output, channel))
            addresses.append(AudioProperty.address(kAudioDevicePropertyMute, Self.output, channel))
        }
        listeners = addresses.compactMap { address in
            AudioListener(object: device, address: address) { [weak self] in self?.listenerFired() }
        }
    }

    func unbind() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    @discardableResult
    func refresh() -> Bool {
        let newVolume = readVolume()
        let newMuted = readMute() ?? (emulatedMuteRestore != nil)
        let changed = abs(newVolume - volume) > 0.001 || newMuted != isMuted
        volume = newVolume
        isMuted = newMuted
        canSetVolume = volumeSettable
        canMute = muteSettable || canSetVolume
        return changed
    }

    public func setVolume(_ value: Double) {
        let value = min(max(value, 0), 1)
        guard writeVolume(value) else {
            hudLog.error("writeVolume failed for \(value, privacy: .public)")
            return
        }
        hudLog.notice("volume set \(value, privacy: .public)")
        volume = value
        if value > 0, isMuted { setMuted(false) }
    }

    public func setMuted(_ muted: Bool) {
        if muteSettable {
            if writeMute(muted) { isMuted = muted }
            return
        }
        guard canSetVolume else { return }
        if muted {
            emulatedMuteRestore = volume
            _ = writeVolume(0)
            isMuted = true
        } else {
            let restore = emulatedMuteRestore ?? volume
            emulatedMuteRestore = nil
            isMuted = false
            if writeVolume(restore) { volume = restore }
        }
    }

    public func toggleMute() { setMuted(!isMuted) }

    private func listenerFired() {
        let previousVolume = volume
        let previousMuted = isMuted
        guard refresh() else { return }
        // Switching devices reports the new device's levels; that is not a user volume change.
        guard Date().timeIntervalSince(boundAt) > 0.6 else { return }
        if abs(previousVolume - volume) > 0.001 || previousMuted != isMuted {
            onExternalChange?()
        }
    }

    // MARK: CoreAudio

    private var virtualMain: AudioObjectPropertyAddress {
        AudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Self.output)
    }

    private func scalar(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioProperty.address(kAudioDevicePropertyVolumeScalar, Self.output, element)
    }

    private func mute(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioProperty.address(kAudioDevicePropertyMute, Self.output, element)
    }

    private var volumeSettable: Bool {
        AudioProperty.isSettable(deviceID, virtualMain)
            || AudioProperty.isSettable(deviceID, scalar(kAudioObjectPropertyElementMain))
            || Self.channels.contains { AudioProperty.isSettable(deviceID, scalar($0)) }
    }

    private var muteSettable: Bool {
        AudioProperty.isSettable(deviceID, mute(kAudioObjectPropertyElementMain))
            || Self.channels.contains { AudioProperty.isSettable(deviceID, mute($0)) }
    }

    private func readVolume() -> Double {
        if let value = AudioProperty.value(deviceID, virtualMain, initial: Float32(0)) { return Double(value) }
        if let value = AudioProperty.value(deviceID, scalar(kAudioObjectPropertyElementMain), initial: Float32(0)) {
            return Double(value)
        }
        let values = Self.channels.compactMap { AudioProperty.value(deviceID, scalar($0), initial: Float32(0)) }
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private func writeVolume(_ value: Double) -> Bool {
        let scalarValue = Float32(value)
        if AudioProperty.set(deviceID, virtualMain, scalarValue) { return true }
        if AudioProperty.set(deviceID, scalar(kAudioObjectPropertyElementMain), scalarValue) { return true }
        var wrote = false
        for channel in Self.channels where AudioProperty.set(deviceID, scalar(channel), scalarValue) {
            wrote = true
        }
        return wrote
    }

    private func readMute() -> Bool? {
        if let value = AudioProperty.value(deviceID, mute(kAudioObjectPropertyElementMain), initial: UInt32(0)) {
            return value != 0
        }
        let values = Self.channels.compactMap { AudioProperty.value(deviceID, mute($0), initial: UInt32(0)) }
        guard !values.isEmpty else { return nil }
        return values.allSatisfy { $0 != 0 }
    }

    private func writeMute(_ muted: Bool) -> Bool {
        let flag: UInt32 = muted ? 1 : 0
        if AudioProperty.set(deviceID, mute(kAudioObjectPropertyElementMain), flag) { return true }
        var wrote = false
        for channel in Self.channels where AudioProperty.set(deviceID, mute(channel), flag) {
            wrote = true
        }
        return wrote
    }
}
