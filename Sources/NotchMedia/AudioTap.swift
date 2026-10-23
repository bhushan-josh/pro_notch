import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import NotchCore
import Observation
import os

/// Publishes live per-band output levels for the waveform, captured with a Core Audio process tap.
/// The tap runs only while it is wanted (setting on, music playing) and a waveform that uses it is on screen.
@MainActor
@Observable
final class LiveWaveform {
    static let shared = LiveWaveform()
    static let bandCount = 6

    private(set) var levels: [CGFloat] = []
    /// The tap is running and audio is actually arriving (silence usually means capture was denied).
    private(set) var hasSignal = false
    private(set) var isRunning = false

    @ObservationIgnored private var capture: AudioTapCapture?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var silentSince: Date?
    @ObservationIgnored private var failedAt: Date?
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    private static let outputAddresses = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice].map {
        AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private init() {}

    func setWanted(_ wanted: Bool) {
        self.wanted = wanted
        update()
    }

    func attach() {
        viewers += 1
        update()
    }

    func detach() {
        viewers = max(0, viewers - 1)
        update()
    }

    private var isNeeded: Bool { wanted && viewers > 0 }

    private func update() {
        if isNeeded {
            stopTask?.cancel()
            stopTask = nil
            startIfNeeded()
        } else if isRunning, stopTask == nil {
            // Short pauses and track gaps should not rebuild the aggregate device.
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.stopNow()
            }
        }
    }

    /// Starts the tap briefly so macOS shows its audio capture prompt.
    func requestPermission() async {
        let wasRunning = isRunning
        startIfNeeded(force: true)
        try? await Task.sleep(for: .seconds(3))
        if !wasRunning, !isNeeded { stopNow() }
    }

    private func startIfNeeded(force: Bool = false) {
        guard !isRunning else { return }
        if !force, let failedAt, Date().timeIntervalSince(failedAt) < 30 { return }
        let capture = AudioTapCapture(bands: Self.bandCount)
        do {
            try capture.start()
        } catch {
            NSLog("Dynamic Notch live waveform unavailable: \(error)")
            failedAt = Date()
            return
        }
        self.capture = capture
        isRunning = true
        silentSince = Date()
        observeOutputDevice()
        publishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                self?.publish()
            }
        }
    }

    private func stopNow() {
        stopTask = nil
        publishTask?.cancel()
        publishTask = nil
        stopObservingOutputDevice()
        capture?.stop()
        capture = nil
        isRunning = false
        hasSignal = false
        levels = []
    }

    /// The aggregate device is bound to the output at creation, so switching output (e.g. to AirPods) needs a new one.
    private func observeOutputDevice() {
        guard deviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scheduleRestart() }
        }
        for var address in Self.outputAddresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        deviceListener = listener
    }

    private func stopObservingOutputDevice() {
        restartTask?.cancel()
        restartTask = nil
        guard let listener = deviceListener else { return }
        for var address in Self.outputAddresses {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        deviceListener = nil
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        // A device switch fires several changes in a row; rebuild once they settle.
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.restartTask = nil
            self.capture?.stop()
            let capture = AudioTapCapture(bands: Self.bandCount)
            do {
                try capture.start()
                self.capture = capture
            } catch {
                NSLog("Dynamic Notch live waveform unavailable: \(error)")
                self.failedAt = Date()
                self.stopNow()
            }
        }
    }

    private func publish() {
        guard let capture else { return }
        let raw = capture.currentLevels()
        let peak = raw.max() ?? 0
        if peak > 0.02 {
            silentSince = nil
            if !hasSignal {
                hasSignal = true
                if !Defaults[MediaSettings.audioCaptureConfirmed] { Defaults[MediaSettings.audioCaptureConfirmed] = true }
            }
        } else if let since = silentSince {
            if Date().timeIntervalSince(since) > 2.5, hasSignal { hasSignal = false }
        } else {
            silentSince = Date()
        }
        let next = raw.map { CGFloat($0) }
        if next != levels { levels = next }
    }
}

/// Owns the tap, its private aggregate device and the IO proc. Not main-actor bound: audio arrives on its own queue.
final class AudioTapCapture: @unchecked Sendable {
    struct Failure: Error, CustomStringConvertible {
        let stage: String
        let status: OSStatus
        var description: String { "\(stage) failed (\(status))" }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "notch.media.audiotap", qos: .userInteractive)
    private let analyzer: SpectrumAnalyzer

    init(bands: Int) {
        analyzer = SpectrumAnalyzer(bands: bands)
    }

    deinit { stop() }

    func currentLevels() -> [Float] { analyzer.levels }

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Dynamic Notch Waveform"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw Failure(stage: "AudioHardwareCreateProcessTap", status: status) }
        tapID = tap

        do {
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
            status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
            guard status == noErr else { throw Failure(stage: "kAudioTapPropertyFormat", status: status) }
            analyzer.configure(format: format)

            let outputUID = try Self.defaultOutputUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Dynamic Notch Waveform",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            var device = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
            guard status == noErr else { throw Failure(stage: "AudioHardwareCreateAggregateDevice", status: status) }
            aggregateID = device

            let analyzer = analyzer
            var proc: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { _, input, _, _, _ in
                analyzer.process(input)
            }
            guard status == noErr, let proc else { throw Failure(stage: "AudioDeviceCreateIOProcIDWithBlock", status: status) }
            procID = proc

            status = AudioDeviceStart(aggregateID, proc)
            guard status == noErr else { throw Failure(stage: "AudioDeviceStart", status: status) }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func defaultOutputUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr else { throw Failure(stage: "DefaultSystemOutputDevice", status: status) }

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw Failure(stage: "DeviceUID", status: status) }
        return uid.takeRetainedValue() as String
    }
}

/// Mixes tapped audio to mono and turns 1024-sample windows into smoothed, log-spaced band levels.
final class SpectrumAnalyzer: @unchecked Sendable {
    private static let log2n: vDSP_Length = 10
    private static let size = 1 << 10

    private let bandCount: Int
    private let lock = OSAllocatedUnfairLock()
    private var published: [Float]

    private var sampleRate: Double = 48_000
    private var channels = 2
    private var isFloat = true
    private var isInterleaved = true

    private let fft: FFTSetup?
    private var window = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var ring = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var ringFill = 0
    private var windowed = [Float](repeating: 0, count: SpectrumAnalyzer.size)
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var imag = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var magnitudes = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var smoothed: [Float]
    private var bandRanges: [Range<Int>] = []

    init(bands: Int) {
        bandCount = bands
        published = Array(repeating: 0, count: bands)
        smoothed = Array(repeating: 0, count: bands)
        fft = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(Self.size), Int32(vDSP_HANN_NORM))
        computeBands()
    }

    deinit {
        if let fft { vDSP_destroy_fftsetup(fft) }
    }

    var levels: [Float] {
        lock.withLock { published }
    }

    func configure(format: AudioStreamBasicDescription) {
        if format.mSampleRate > 0 { sampleRate = format.mSampleRate }
        channels = max(1, Int(format.mChannelsPerFrame))
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 || format.mFormatID == kAudioFormatLinearPCM && format.mBitsPerChannel == 32
        isInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        computeBands()
    }

    private func computeBands() {
        let edges: [Double] = [50, 160, 400, 1_000, 2_500, 6_000, 14_000]
        let binWidth = sampleRate / Double(Self.size)
        let maxBin = Self.size / 2 - 1
        var ranges: [Range<Int>] = []
        for index in 0..<bandCount {
            let lowEdge = edges[min(index, edges.count - 2)]
            let highEdge = edges[min(index + 1, edges.count - 1)]
            let low = max(1, min(maxBin, Int(lowEdge / binWidth)))
            let high = max(low + 1, min(maxBin + 1, Int(highEdge / binWidth)))
            ranges.append(low..<high)
        }
        bandRanges = ranges
    }

    func process(_ input: UnsafePointer<AudioBufferList>) {
        guard isFloat else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let firstData = first.mData else { return }

        if isInterleaved || buffers.count == 1 {
            let stride = max(1, Int(first.mNumberChannels))
            let samples = firstData.assumingMemoryBound(to: Float.self)
            let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * stride)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<stride { sum += samples[frame * stride + channel] }
                append(sum / Float(stride))
            }
        } else {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let count = buffers.count
            for frame in 0..<frames {
                var sum: Float = 0
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    sum += data.assumingMemoryBound(to: Float.self)[frame]
                }
                append(sum / Float(count))
            }
        }
    }

    private func append(_ sample: Float) {
        ring[ringFill] = sample
        ringFill += 1
        if ringFill == Self.size {
            analyze()
            // Half overlap keeps the update rate near 90 Hz at 48 kHz without extra latency.
            let half = Self.size / 2
            for index in 0..<half { ring[index] = ring[index + half] }
            ringFill = half
        }
    }

    private func analyze() {
        guard let fft else { return }
        let n = vDSP_Length(Self.size)
        vDSP_vmul(ring, 1, window, 1, &windowed, 1, n)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, n / 2)
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                magnitudes.withUnsafeMutableBufferPointer { mags in
                    vDSP_zvmags(&split, 1, mags.baseAddress!, 1, n / 2)
                }
            }
        }

        let scale = 2 / Float(Self.size)
        for (band, range) in bandRanges.enumerated() {
            var peak: Float = 0
            var total: Float = 0
            for bin in range {
                let value = magnitudes[bin]
                total += value
                peak = max(peak, value)
            }
            let mean = total / Float(range.count)
            let amplitude = sqrtf(mean * 0.5 + peak * 0.5) * scale
            // Higher bands carry less energy in most music; tilt them up so all bars move.
            let db = 20 * log10f(max(amplitude, 1e-7)) + Float(band) * 3.5
            let target = min(max((db + 58) / 50, 0), 1)
            let previous = smoothed[band]
            let factor: Float = target > previous ? 0.55 : 0.18
            smoothed[band] = previous + (target - previous) * factor
        }
        let snapshot = smoothed
        lock.withLock { published = snapshot }
    }
}
