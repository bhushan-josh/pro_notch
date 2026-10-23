import NotchCore
import SwiftUI

struct TimersPage: View {
    let manager: TimerManager
    @State private var showsCustom = false

    var body: some View {
        Group {
            switch manager.phase {
            case .running, .paused:
                TimerRunningView(manager: manager)
            case .finished:
                TimerFinishedView(manager: manager)
            case .idle:
                if showsCustom {
                    TimerCustomPicker(manager: manager) { withAnimation(.notchSnappy) { showsCustom = false } }
                } else {
                    TimerPresetGrid(manager: manager) { withAnimation(.notchSnappy) { showsCustom = true } }
                }
            }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.notchSnappy, value: manager.phase)
        .onChange(of: manager.phase) { _, phase in
            if phase != .idle { showsCustom = false }
        }
    }
}

// MARK: Idle

private struct TimerPresetGrid: View {
    let manager: TimerManager
    let onCustom: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "timer").foregroundStyle(.orange)
                Text("Start a Timer").foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 11, weight: .semibold))
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(manager.presets, id: \.self) { minutes in
                        let label = TimerFormat.preset(minutes)
                        TimerChip(help: "Start a \(TimerFormat.length(TimeInterval(minutes * 60))) timer") {
                            manager.start(TimeInterval(minutes * 60))
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(label.value).font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                                Text(label.unit).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    TimerChip(help: "Custom duration", action: onCustom) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            Text("Custom").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TimerChip<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.white.opacity(isHovering ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

private struct TimerCustomPicker: View {
    let manager: TimerManager
    let onBack: () -> Void
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0

    private var total: Int { hours * 3600 + minutes * 60 + seconds }

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .top, spacing: 2) {
                DurationWheel(value: $hours, range: 0...99, unit: "hr")
                separator
                DurationWheel(value: $minutes, range: 0...59, unit: "min")
                separator
                DurationWheel(value: $seconds, range: 0...59, unit: "sec")
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 8) {
                Button {
                    Defaults[TimersSettings.lastCustom] = total
                    manager.start(TimeInterval(total))
                } label: {
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(total > 0 ? .black : .white.opacity(0.4))
                        .frame(width: 74, height: 30)
                        .background(total > 0 ? Color.orange : Color.white.opacity(0.08), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(total == 0)
                Button(action: onBack) {
                    Text("Presets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 74, height: 30)
                        .background(.white.opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let last = max(1, Defaults[TimersSettings.lastCustom])
            hours = min(last / 3600, 99)
            minutes = last / 60 % 60
            seconds = last % 60
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 22)
    }
}

/// A compact wheel: chevrons step by one, wrapping around, and a vertical drag on the number scrubs it.
private struct DurationWheel: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    @State private var dragStart: Int?

    var body: some View {
        VStack(spacing: 0) {
            chevron("chevron.up") { step(1) }
            Text(String(format: "%02d", value))
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 46, height: 34)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            let start = dragStart ?? value
                            dragStart = start
                            let offset = Int((-drag.translation.height / 10).rounded())
                            set(start + offset)
                        }
                        .onEnded { _ in dragStart = nil }
                )
            chevron("chevron.down") { step(-1) }
            Text(unit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func chevron(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 46, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ delta: Int) {
        let count = range.count
        value = range.lowerBound + ((value - range.lowerBound + delta) % count + count) % count
    }

    private func set(_ newValue: Int) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
    }
}

// MARK: Running

private struct TimerRunningView: View {
    let manager: TimerManager

    var body: some View {
        let paused = manager.phase == .paused
        TimerTicker(manager: manager) { now in
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Image(systemName: paused ? "pause.fill" : "timer")
                            Text(TimerFormat.length(manager.duration))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        Text(TimerFormat.clock(manager.remaining(at: now)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(paused ? 0.5 : 1)
                        Group {
                            if let end = manager.endDate {
                                Label { Text(end, style: .time) } icon: { Image(systemName: "bell.fill") }
                            } else {
                                Text("Paused")
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        TimerCircleButton(help: "Add 1 Minute") { manager.addMinute() } label: {
                            Text("+1").font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        TimerCircleButton(fill: .orange.opacity(0.25), tint: .orange, help: paused ? "Resume" : "Pause") {
                            manager.togglePause()
                        } label: {
                            Image(systemName: paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 14, weight: .bold))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        TimerCircleButton(help: "Cancel") { manager.cancel() } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        }
                    }
                }
                NotchProgressBar(value: manager.remainingFraction(at: now), style: .white, tint: .orange, height: 5)
                    .opacity(paused ? 0.5 : 1)
            }
        }
        .labelStyle(TightLabelStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: Finished

private struct TimerFinishedView: View {
    let manager: TimerManager

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Image(systemName: "bell.fill")
                        .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.2)))
                    Text(TimerFormat.length(manager.initialDuration))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
                Text("Timer Done")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                TimerCircleButton(help: "Repeat") { manager.repeatLast() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .bold))
                }
                Button { manager.dismissAlert() } label: {
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 36)
                        .background(.orange, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
