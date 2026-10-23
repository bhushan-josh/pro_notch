import NotchCore
import Observation
import SwiftUI

@MainActor
public final class StatsFeature: NotchFeature {
    public static let pageID = "stats"

    private let monitor = StatsMonitor()
    private lazy var idleProvider = StatsIdleProvider(monitor: monitor)
    private var settingsObserver: AnyObject?

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        registry.register(settingsPane: SettingsPane(id: "stats", title: "Stats", symbol: "chart.bar.xaxis", color: .mint, category: .general, order: 30) {
            StatsSettingsView()
        })
        registry.register(idleProvider: idleProvider)
        monitor.start()
        apply()
        settingsObserver = Defaults.observe([StatsSettings.enabled.name, StatsSettings.closedNotchMetric.name]) { [weak self] in
            self?.apply()
        }
    }

    public func stop() {
        settingsObserver = nil
        updatePage(visible: false)
        idleProvider.update(metric: .none)
        monitor.shutdown()
    }

    private func apply() {
        updatePage(visible: Defaults[StatsSettings.enabled])
        idleProvider.update(metric: Defaults[StatsSettings.closedNotchMetric])
    }

    private func updatePage(visible: Bool) {
        let registry = NotchRegistry.shared
        if visible {
            guard !registry.pages.contains(where: { $0.id == Self.pageID }) else { return }
            let monitor = monitor
            withAnimation(.notchSnappy) {
                registry.register(page: NotchPage(id: Self.pageID, title: "Stats", symbol: "chart.bar.xaxis", order: 50) {
                    StatsPage(monitor: monitor)
                })
            }
        } else {
            for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
                model.selectedPageID = NotchModel.homePageID
            }
            withAnimation(.notchSnappy) { registry.unregister(pageID: Self.pageID) }
        }
    }
}

/// Shows one live metric in the closed notch's wings while nothing else is going on.
@MainActor
@Observable
final class StatsIdleProvider: IdleActivityProvider {
    private(set) var metric = StatsClosedMetric.none
    private(set) var idleActivityUpdatedAt = Date.distantPast

    @ObservationIgnored private let monitor: StatsMonitor

    init(monitor: StatsMonitor) {
        self.monitor = monitor
    }

    func update(metric: StatsClosedMetric) {
        guard metric != self.metric else { return }
        self.metric = metric
        idleActivityUpdatedAt = Date()
    }

    var idleActivity: LiveActivity? {
        guard metric != .none else { return nil }
        let metric = metric
        let monitor = monitor
        return LiveActivity(
            id: "stats.closed",
            category: .other,
            priority: .idle,
            leadingWidth: 22,
            trailingWidth: metric == .network ? 40 : 34,
            leading: { StatsWingLeading(metric: metric, monitor: monitor) },
            trailing: { StatsWingTrailing(metric: metric, monitor: monitor) },
            onTap: {
                NotchManager.shared.activeModel?.open(page: Defaults[StatsSettings.enabled] ? StatsFeature.pageID : nil)
            }
        )
    }
}

struct StatsSettingsView: View {
    @AppStorage(StatsSettings.enabled) private var enabled
    @AppStorage(StatsSettings.showCPU) private var showCPU
    @AppStorage(StatsSettings.showPerCore) private var showPerCore
    @AppStorage(StatsSettings.showGPU) private var showGPU
    @AppStorage(StatsSettings.showMemory) private var showMemory
    @AppStorage(StatsSettings.showNetwork) private var showNetwork
    @AppStorage(StatsSettings.showDisk) private var showDisk
    @AppStorage(StatsSettings.sampleInterval) private var interval
    @AppStorage(StatsSettings.closedNotchMetric) private var closedMetric

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Show Stats Page", info: "Adds a tab with CPU, GPU, memory, network and disk usage. Stats are measured only while the tab is open.", isOn: $enabled)
            }
            if enabled {
                Section("Metrics") {
                    Toggle("CPU", isOn: $showCPU)
                    if showCPU {
                        SettingsToggle("Per-Core Bars", info: "Shows each core's load instead of the usage graph.", isOn: $showPerCore)
                    }
                    Toggle("GPU", isOn: $showGPU)
                    Toggle("Memory", isOn: $showMemory)
                    Toggle("Network", isOn: $showNetwork)
                    Toggle("Disk", isOn: $showDisk)
                }
            }
            Section {
                Picker("Show in Closed Notch", selection: $closedMetric) {
                    ForEach(StatsClosedMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Closed Notch")
            } footer: {
                Text("Measured only while it is on screen.")
            }
            Section {
                SettingsSlider("Sample Every", value: $interval, in: 1...5, step: 1, format: { "\(Int($0)) s" })
            } header: {
                Text("Sampling")
            } footer: {
                Text("Longer intervals use less energy.")
            }
        }
    }
}
