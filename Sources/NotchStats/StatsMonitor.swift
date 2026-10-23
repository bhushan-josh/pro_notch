import AppKit
import NotchCore
import Observation

/// Publishes sampled stats on the main actor. Sampling runs only while a consumer (the Stats page or the
/// closed-notch wing) is on screen, counted per window since several notches can show at once.
@MainActor
@Observable
final class StatsMonitor {
    static let historyLength = 60

    enum Consumer {
        case page, wing
    }

    private(set) var cpu: Double?
    private(set) var cores: [Double] = []
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryUsed: UInt64?
    private(set) var pressure: MemoryPressure?
    private(set) var memoryHistory: [Double] = []
    private(set) var gpu: Double?
    private(set) var hasGPU = true
    private(set) var gpuHistory: [Double] = []
    private(set) var download: Double?
    private(set) var upload: Double?
    private(set) var downloadHistory: [Double] = []
    private(set) var uploadHistory: [Double] = []
    private(set) var disk: DiskSpace?

    @ObservationIgnored let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @ObservationIgnored private var sampler: StatsSampler?
    @ObservationIgnored private var pageUsers = 0
    @ObservationIgnored private var wingUsers = 0
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var sessionInactive = false
    @ObservationIgnored private var running: (metrics: StatsMetrics, interval: TimeInterval)?
    @ObservationIgnored private var settingsObserver: AnyObject?
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []

    init() {
        sampler = StatsSampler { [weak self] sample in
            Task { @MainActor in self?.apply(sample) }
        }
    }

    var memoryFraction: Double? {
        guard let memoryUsed, memoryTotal > 0 else { return nil }
        return min(Double(memoryUsed) / Double(memoryTotal), 1)
    }

    func start() {
        let keys = [
            StatsSettings.showCPU, StatsSettings.showGPU, StatsSettings.showMemory,
            StatsSettings.showNetwork, StatsSettings.showDisk,
        ].map(\.name) + [StatsSettings.sampleInterval.name, StatsSettings.closedNotchMetric.name]
        settingsObserver = Defaults.observe(keys) { [weak self] in self?.updateSampling() }

        workspaceTokens = [
            observeWorkspace(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true },
            observeWorkspace(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false },
            observeWorkspace(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true },
            observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false },
        ]
    }

    private func observeWorkspace(_ name: Notification.Name, _ change: @escaping @MainActor (StatsMonitor) -> Void) -> NSObjectProtocol {
        NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                change(self)
                self.updateSampling()
            }
        }
    }

    func shutdown() {
        settingsObserver = nil
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        pageUsers = 0
        wingUsers = 0
        updateSampling()
    }

    func acquire(_ consumer: Consumer) {
        switch consumer {
        case .page: pageUsers += 1
        case .wing: wingUsers += 1
        }
        updateSampling()
    }

    func release(_ consumer: Consumer) {
        switch consumer {
        case .page: pageUsers = max(0, pageUsers - 1)
        case .wing: wingUsers = max(0, wingUsers - 1)
        }
        updateSampling()
    }

    private var neededMetrics: StatsMetrics {
        guard !screensAsleep, !sessionInactive else { return [] }
        var metrics: StatsMetrics = []
        if pageUsers > 0, Defaults[StatsSettings.enabled] {
            if Defaults[StatsSettings.showCPU] { metrics.insert(.cpu) }
            if Defaults[StatsSettings.showGPU] { metrics.insert(.gpu) }
            if Defaults[StatsSettings.showMemory] { metrics.insert(.memory) }
            if Defaults[StatsSettings.showNetwork] { metrics.insert(.network) }
            if Defaults[StatsSettings.showDisk] { metrics.insert(.disk) }
        }
        if wingUsers > 0 {
            switch Defaults[StatsSettings.closedNotchMetric] {
            case .none: break
            case .cpu: metrics.insert(.cpu)
            case .memory: metrics.insert(.memory)
            case .network: metrics.insert(.network)
            }
        }
        return metrics
    }

    private func updateSampling() {
        guard let sampler else { return }
        let metrics = neededMetrics
        let interval = StatsSettings.interval
        if metrics.isEmpty {
            guard running != nil else { return }
            running = nil
            sampler.stop()
        } else {
            if let running, running.metrics == metrics, running.interval == interval { return }
            running = (metrics, interval)
            sampler.run(interval: interval, metrics: metrics)
        }
    }

    private func apply(_ sample: StatsSample) {
        guard running != nil else { return }
        if let value = sample.cpu {
            cpu = value
            cores = sample.cores
            Self.append(value, to: &cpuHistory)
        }
        if let used = sample.memoryUsed {
            memoryUsed = used
            if pressure != sample.pressure { pressure = sample.pressure }
            if let memoryFraction { Self.append(memoryFraction, to: &memoryHistory) }
        }
        if sample.gpuSampled {
            if hasGPU != (sample.gpu != nil) { hasGPU = sample.gpu != nil }
            if let value = sample.gpu {
                gpu = value
                Self.append(value, to: &gpuHistory)
            }
        }
        if let down = sample.download, let up = sample.upload {
            download = down
            upload = up
            Self.append(down, to: &downloadHistory)
            Self.append(up, to: &uploadHistory)
        }
        if let value = sample.disk, value != disk { disk = value }
    }

    private static func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
    }
}
