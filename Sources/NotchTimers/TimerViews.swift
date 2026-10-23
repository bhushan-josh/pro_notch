import NotchCore
import SwiftUI

/// Re-renders its content once a second, on the countdown's own second boundaries, and only while
/// the timer runs. Paused, idle and finished timers render once.
struct TimerTicker<Content: View>: View {
    let manager: TimerManager
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        // Always a TimelineView so pausing keeps the content's identity (hover state, symbol transitions).
        TimelineView(CountdownSchedule(end: manager.phase == .running ? manager.endDate : nil)) { _ in
            content(Date())
        }
    }
}

/// Entries at each whole second before `end`, so the displayed value flips exactly on the second.
/// With no end date there is a single entry and the view never ticks.
struct CountdownSchedule: TimelineSchedule {
    let end: Date?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var first: Date? = startDate
        guard let end, end > startDate else {
            return AnyIterator {
                defer { first = nil }
                return first
            }
        }
        var tick = end.addingTimeInterval(-end.timeIntervalSince(startDate).rounded(.down))
        if tick <= startDate { tick = tick.addingTimeInterval(1) }
        return AnyIterator {
            if let date = first {
                first = nil
                return date
            }
            guard tick <= end else { return nil }
            defer { tick = tick.addingTimeInterval(1) }
            return tick
        }
    }
}

struct TimerRing: View {
    var fraction: Double
    var tint: Color = .orange
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: Closed notch

struct TimerLeadingWing: View {
    let manager: TimerManager

    var body: some View {
        TimerTicker(manager: manager) { now in
            TimerRing(fraction: manager.remainingFraction(at: now), lineWidth: 2.5)
                .frame(width: 16, height: 16)
        }
        .opacity(manager.phase == .paused ? 0.45 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimerTrailingWing: View {
    let manager: TimerManager

    var body: some View {
        TimerTicker(manager: manager) { now in
            Text(TimerFormat.clock(manager.remaining(at: now)))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.orange)
                .lineLimit(1)
                .fixedSize()
        }
        .opacity(manager.phase == .paused ? 0.45 : 1)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct TimerDoneLeading: View {
    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.orange)
            .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1.2)))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimerDoneTrailing: View {
    var body: some View {
        Text("0:00")
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct TimerDoneStrip: View {
    let manager: TimerManager

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Timer Done")
                    .font(.system(size: 12, weight: .semibold))
                Text(TimerFormat.length(manager.initialDuration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            TimerCircleButton(size: 24, fill: .white.opacity(0.14), help: "Repeat") {
                manager.repeatLast()
            } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .bold))
            }
            Button {
                manager.dismissAlert()
            } label: {
                Text("Stop")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .frame(height: 24)
                    .background(.orange, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 6)
    }
}

// MARK: Shared controls

struct TimerCircleButton<Label: View>: View {
    var size: CGFloat = 36
    var fill: Color = .white.opacity(0.12)
    var tint: Color = .white
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(fill.opacity(isHovering ? 1.6 : 1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

// MARK: Lock screen

struct TimerLockScreenView: View {
    let manager: TimerManager

    var body: some View {
        if manager.phase != .idle {
            HStack(spacing: 14) {
                ZStack {
                    TimerTicker(manager: manager) { now in
                        TimerRing(fraction: manager.phase == .finished ? 0 : manager.remainingFraction(at: now), lineWidth: 4)
                    }
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    TimerTicker(manager: manager) { now in
                        Text(TimerFormat.clock(manager.remaining(at: now)))
                            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                    }
                    .opacity(manager.phase == .paused ? 0.55 : 1)
                }
                Spacer(minLength: 8)
                if manager.phase == .running, let end = manager.endDate {
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: "bell.fill")
                        Text(end, style: .time)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
    }

    private var symbol: String {
        switch manager.phase {
        case .paused: "pause.fill"
        case .finished: "bell.fill"
        case .idle, .running: "timer"
        }
    }

    private var title: String {
        switch manager.phase {
        case .paused: "Paused"
        case .finished: "Timer Done"
        case .idle, .running: "Timer"
        }
    }
}
