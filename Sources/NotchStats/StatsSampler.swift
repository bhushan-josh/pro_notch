import Darwin
import Foundation
import IOKit

struct StatsMetrics: OptionSet, Sendable {
    let rawValue: Int

    static let cpu = Self(rawValue: 1 << 0)
    static let memory = Self(rawValue: 1 << 1)
    static let gpu = Self(rawValue: 1 << 2)
    static let network = Self(rawValue: 1 << 3)
    static let disk = Self(rawValue: 1 << 4)
}

enum MemoryPressure: Sendable {
    case normal, warning, critical
}

struct DiskSpace: Equatable, Sendable {
    var free: Int64
    var total: Int64

    var usedFraction: Double { total > 0 ? Double(total - free) / Double(total) : 0 }
}

/// One tick's readings; a nil field was not sampled this tick or has no baseline yet.
struct StatsSample: Sendable {
    var cpu: Double?
    var cores: [Double] = []
    var memoryUsed: UInt64?
    var pressure: MemoryPressure?
    var gpuSampled = false
    var gpu: Double?
    var download: Double?
    var upload: Double?
    var disk: DiskSpace?
}

/// Reads system counters on its own serial queue. All mutable state is touched only on `queue`.
final class StatsSampler: @unchecked Sendable {
    private static let diskRefreshNanoseconds: UInt64 = 30_000_000_000
    /// Tunnels and bridges carry traffic that is already counted on the physical interface.
    private static let ignoredInterfacePrefixes = ["utun", "ipsec", "awdl", "llw", "bridge", "gif", "stf", "anpi"]

    private struct CPUTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private let queue = DispatchQueue(label: "DynamicNotch.stats", qos: .utility)
    private let deliver: @Sendable (StatsSample) -> Void
    private let host = mach_host_self()
    private let pageSize: UInt64

    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 0
    private var metrics: StatsMetrics = []
    private var previousTicks: [CPUTicks] = []
    private var previousNetwork: [String: (received: UInt32, sent: UInt32)] = [:]
    private var previousNetworkTime: UInt64 = 0
    private var gpuServices: [io_object_t]?
    private var lastDiskRead: UInt64?

    init(deliver: @escaping @Sendable (StatsSample) -> Void) {
        self.deliver = deliver
        var size: vm_size_t = 0
        host_page_size(host, &size)
        pageSize = size > 0 ? UInt64(size) : 16384
    }

    func run(interval: TimeInterval, metrics: StatsMetrics) {
        queue.async { [self] in
            let added = !metrics.isSubset(of: self.metrics)
            self.metrics = metrics
            resetBaselines(keeping: metrics)
            guard timer == nil || interval != self.interval || added else { return }
            timer?.cancel()
            self.interval = interval
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(interval * 250)))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            metrics = []
            resetBaselines(keeping: [])
        }
    }

    private func resetBaselines(keeping metrics: StatsMetrics) {
        if !metrics.contains(.cpu) { previousTicks = [] }
        if !metrics.contains(.network) {
            previousNetwork = [:]
            previousNetworkTime = 0
        }
        if !metrics.contains(.gpu) {
            gpuServices?.forEach { IOObjectRelease($0) }
            gpuServices = nil
        }
    }

    private func tick() {
        var sample = StatsSample()
        if metrics.contains(.cpu) { readCPU(into: &sample) }
        if metrics.contains(.memory) { readMemory(into: &sample) }
        if metrics.contains(.gpu) {
            sample.gpuSampled = true
            sample.gpu = readGPU()
        }
        if metrics.contains(.network) { readNetwork(into: &sample) }
        if metrics.contains(.disk) {
            let now = DispatchTime.now().uptimeNanoseconds
            if lastDiskRead.map({ now - $0 >= Self.diskRefreshNanoseconds }) ?? true {
                lastDiskRead = now
                sample.disk = Self.readDisk()
            }
        }
        deliver(sample)
    }

    // MARK: CPU

    private func readCPU(into sample: inout StatsSample) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        let ticks = (0..<Int(cpuCount)).map { cpu in
            let base = cpu * stride
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return }

        var busyTotal: UInt64 = 0
        var allTotal: UInt64 = 0
        sample.cores = zip(ticks, previousTicks).map { now, before in
            let busy = UInt64(now.user &- before.user) + UInt64(now.system &- before.system) + UInt64(now.nice &- before.nice)
            let total = busy + UInt64(now.idle &- before.idle)
            busyTotal += busy
            allTotal += total
            return total > 0 ? Double(busy) / Double(total) : 0
        }
        sample.cpu = allTotal > 0 ? Double(busyTotal) / Double(allTotal) : 0
    }

    // MARK: Memory

    private func readMemory(into sample: inout StatsSample) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = host
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        sample.memoryUsed = pages * pageSize
        sample.pressure = Self.memoryPressure()
    }

    private static func memoryPressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }

    // MARK: GPU

    private func readGPU() -> Double? {
        if gpuServices == nil { gpuServices = Self.accelerators() }
        var utilization: Double?
        for service in gpuServices ?? [] {
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber
            else { continue }
            utilization = max(utilization ?? 0, min(max(value.doubleValue / 100, 0), 1))
        }
        return utilization
    }

    private static func accelerators() -> [io_object_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [io_object_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            services.append(service)
        }
        return services
    }

    // MARK: Network

    private func readNetwork(into sample: inout StatsSample) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return }
        defer { freeifaddrs(head) }

        var counters: [String: (received: UInt32, sent: UInt32)] = [:]
        var cursor = head
        while let entry = cursor?.pointee {
            cursor = entry.ifa_next
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let data = entry.ifa_data
            else { continue }
            let name = String(cString: entry.ifa_name)
            guard !Self.ignoredInterfacePrefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            let stats = data.load(as: if_data.self)
            counters[name] = (stats.ifi_ibytes, stats.ifi_obytes)
        }

        let now = DispatchTime.now().uptimeNanoseconds
        defer {
            previousNetwork = counters
            previousNetworkTime = now
        }
        guard previousNetworkTime > 0, now > previousNetworkTime else { return }
        let elapsed = Double(now - previousNetworkTime) / 1_000_000_000
        var received: UInt64 = 0
        var sent: UInt64 = 0
        // if_data counters are 32-bit, so wrapping subtraction survives a rollover between samples.
        for (name, current) in counters {
            guard let before = previousNetwork[name] else { continue }
            received += UInt64(current.received &- before.received)
            sent += UInt64(current.sent &- before.sent)
        }
        sample.download = Double(received) / elapsed
        sample.upload = Double(sent) / elapsed
    }

    // MARK: Disk

    private static func readDisk() -> DiskSpace? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        return DiskSpace(free: free, total: Int64(total))
    }
}
