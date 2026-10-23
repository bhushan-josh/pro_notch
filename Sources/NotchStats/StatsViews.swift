import NotchCore
import SwiftUI

enum StatsStyle {
    static func load(_ fraction: Double) -> Color {
        if fraction >= 0.85 { return .red }
        if fraction >= 0.6 { return .yellow }
        return .green
    }

    static func memory(_ pressure: MemoryPressure?, fraction: Double?) -> Color {
        switch pressure {
        case .critical: .red
        case .warning: .yellow
        case .normal: .green
        case nil: load(fraction ?? 0)
        }
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "--" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "--" }
        return "\(scaled(bytesPerSecond, units: ["B", "KB", "MB", "GB"], separator: " "))/s"
    }

    /// Short form for the closed notch, e.g. "1.2M".
    static func compactRate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "--" }
        return scaled(bytesPerSecond, units: ["B", "K", "M", "G"], separator: "")
    }

    private static func scaled(_ value: Double, units: [String], separator: String) -> String {
        var value = max(value, 0)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let number = unit > 0 && value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
        return number + separator + units[unit]
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value < 100 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }

    static func diskSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: Page

struct StatsPage: View {
    let monitor: StatsMonitor
    @AppStorage(StatsSettings.showCPU) private var showCPU
    @AppStorage(StatsSettings.showGPU) private var showGPU
    @AppStorage(StatsSettings.showMemory) private var showMemory
    @AppStorage(StatsSettings.showNetwork) private var showNetwork
    @AppStorage(StatsSettings.showDisk) private var showDisk

    var body: some View {
        let gpuVisible = showGPU && monitor.hasGPU
        VStack(spacing: 8) {
            if showCPU || gpuVisible || showMemory || showNetwork {
                HStack(spacing: 8) {
                    if showCPU { CPUTile(monitor: monitor) }
                    if gpuVisible { GPUTile(monitor: monitor) }
                    if showMemory { MemoryTile(monitor: monitor) }
                    if showNetwork { NetworkTile(monitor: monitor) }
                }
                .frame(maxHeight: .infinity)
            }
            if showDisk { DiskRow(monitor: monitor) }
            if !showCPU && !showGPU && !showMemory && !showNetwork && !showDisk {
                Text("Turn on stats in Settings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { monitor.acquire(.page) }
        .onDisappear { monitor.release(.page) }
    }
}

private struct StatTile<Content: View, Graph: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content
    @ViewBuilder let graph: Graph

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            content
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 2)
            graph.frame(height: 22)
        }
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct TileValue: View {
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            Text(detail)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct CPUTile: View {
    let monitor: StatsMonitor
    @AppStorage(StatsSettings.showPerCore) private var showPerCore

    var body: some View {
        let tint = StatsStyle.load(monitor.cpu ?? 0)
        StatTile(title: "CPU", symbol: "cpu", tint: tint) {
            TileValue(value: StatsStyle.percent(monitor.cpu), detail: monitor.cores.isEmpty ? "Usage" : "\(monitor.cores.count) cores")
        } graph: {
            if showPerCore {
                CoreBars(values: monitor.cores)
            } else {
                Sparkline(values: monitor.cpuHistory, tint: tint)
            }
        }
    }
}

private struct GPUTile: View {
    let monitor: StatsMonitor

    var body: some View {
        let tint = StatsStyle.load(monitor.gpu ?? 0)
        StatTile(title: "GPU", symbol: "cube.transparent", tint: tint) {
            TileValue(value: StatsStyle.percent(monitor.gpu), detail: "Usage")
        } graph: {
            Sparkline(values: monitor.gpuHistory, tint: tint)
        }
    }
}

private struct MemoryTile: View {
    let monitor: StatsMonitor

    var body: some View {
        let fraction = monitor.memoryFraction
        let tint = StatsStyle.memory(monitor.pressure, fraction: fraction)
        let detail = monitor.memoryUsed.map { "\(StatsStyle.gigabytes($0)) of \(StatsStyle.gigabytes(monitor.memoryTotal)) GB" } ?? "--"
        StatTile(title: "Memory", symbol: "memorychip", tint: tint) {
            TileValue(value: StatsStyle.percent(fraction), detail: detail)
        } graph: {
            Sparkline(values: monitor.memoryHistory, tint: tint)
        }
    }
}

private struct NetworkTile: View {
    let monitor: StatsMonitor
    private static let downTint = Color.cyan
    private static let upTint = Color.orange
    /// Keeps idle traffic from filling the graph.
    private static let minimumScale = 50_000.0

    var body: some View {
        let peak = max(monitor.downloadHistory.max() ?? 0, monitor.uploadHistory.max() ?? 0, Self.minimumScale)
        StatTile(title: "Network", symbol: "network", tint: Self.downTint) {
            VStack(alignment: .leading, spacing: 1) {
                rate(symbol: "arrow.down", value: monitor.download, tint: Self.downTint)
                rate(symbol: "arrow.up", value: monitor.upload, tint: Self.upTint)
            }
        } graph: {
            ZStack {
                Sparkline(values: monitor.downloadHistory.map { $0 / peak }, tint: Self.downTint)
                Sparkline(values: monitor.uploadHistory.map { $0 / peak }, tint: Self.upTint, filled: false)
            }
        }
    }

    private func rate(symbol: String, value: Double?, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(tint)
            Text(StatsStyle.rate(value))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
        }
    }
}

private struct DiskRow: View {
    let monitor: StatsMonitor

    var body: some View {
        let disk = monitor.disk
        let used = disk?.usedFraction ?? 0
        HStack(spacing: 6) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Disk")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            NotchProgressBar(value: used, style: .white, tint: StatsStyle.load(used), height: 4)
            Text(disk.map { "\(StatsStyle.diskSize($0.free)) free of \(StatsStyle.diskSize($0.total))" } ?? "--")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 14)
    }
}

// MARK: Graphs

struct Sparkline: View {
    /// Fractions in 0...1, oldest first.
    let values: [Double]
    let tint: Color
    var filled = true

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(StatsMonitor.historyLength - 1)
            let startX = size.width - step * CGFloat(values.count - 1)
            var line = Path()
            for (index, value) in values.enumerated() {
                let clamped = CGFloat(min(max(value, 0), 1))
                let point = CGPoint(x: startX + step * CGFloat(index), y: 1 + (size.height - 2) * (1 - clamped))
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: startX, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let spacing: CGFloat = values.count > 12 ? 1 : 1.5
            let width = max((size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count), 1)
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * (width + spacing)
                let track = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: track, cornerRadius: width / 2), with: .color(.white.opacity(0.1)))
                let height = max(size.height * CGFloat(min(max(value, 0), 1)), width)
                let bar = CGRect(x: x, y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: width / 2), with: .color(StatsStyle.load(value)))
            }
        }
    }
}

// MARK: Closed notch

struct StatsWingLeading: View {
    let metric: StatsClosedMetric
    let monitor: StatsMonitor

    var body: some View {
        Image(systemName: metric.symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tint: Color {
        switch metric {
        case .cpu: StatsStyle.load(monitor.cpu ?? 0)
        case .memory: StatsStyle.memory(monitor.pressure, fraction: monitor.memoryFraction)
        case .network, .none: .cyan
        }
    }
}

struct StatsWingTrailing: View {
    let metric: StatsClosedMetric
    let monitor: StatsMonitor

    var body: some View {
        content
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .onAppear { monitor.acquire(.wing) }
            .onDisappear { monitor.release(.wing) }
    }

    @ViewBuilder
    private var content: some View {
        switch metric {
        case .cpu:
            percent(monitor.cpu)
        case .memory:
            percent(monitor.memoryFraction)
        case .network:
            VStack(alignment: .trailing, spacing: 0) {
                compact(symbol: "arrow.down", value: monitor.download)
                compact(symbol: "arrow.up", value: monitor.upload)
            }
        case .none:
            EmptyView()
        }
    }

    private func percent(_ value: Double?) -> some View {
        Text(StatsStyle.percent(value))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
    }

    private func compact(symbol: String, value: Double?) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol).font(.system(size: 6, weight: .heavy))
            Text(StatsStyle.compactRate(value)).font(.system(size: 9, weight: .semibold).monospacedDigit())
        }
    }
}
