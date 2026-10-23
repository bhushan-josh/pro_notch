import Foundation
import NotchCore

public enum StatsClosedMetric: String, CaseIterable, Sendable {
    case none, cpu, memory, network

    var title: String {
        switch self {
        case .none: "None"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.slash"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "network"
        }
    }
}

public enum StatsSettings {
    public static let enabled = SettingKey("stats.enabled", default: true)
    public static let showCPU = SettingKey("stats.showCPU", default: true)
    public static let showPerCore = SettingKey("stats.showPerCore", default: false)
    public static let showGPU = SettingKey("stats.showGPU", default: true)
    public static let showMemory = SettingKey("stats.showMemory", default: true)
    public static let showNetwork = SettingKey("stats.showNetwork", default: true)
    public static let showDisk = SettingKey("stats.showDisk", default: true)
    /// Seconds between samples, 1...5.
    public static let sampleInterval = SettingKey("stats.sampleInterval", default: 1.0)
    public static let closedNotchMetric = SettingKey("stats.closedNotchMetric", default: StatsClosedMetric.none)

    static var interval: TimeInterval { min(max(Defaults[sampleInterval], 1), 5) }
}
