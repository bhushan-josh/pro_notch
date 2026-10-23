import AppKit
import NotchCore
import Observation
import SwiftUI

struct Sensors: Equatable {
    var camera: Bool
    var microphone: Bool

    var any: Bool { camera || microphone }
}

@MainActor
@Observable
final class PrivacyController {
    private(set) var sensors = Sensors(camera: false, microphone: false)

    @ObservationIgnored private let camera = CameraMonitor()
    @ObservationIgnored private let microphone = MicrophoneMonitor()
    @ObservationIgnored private var shown: Sensors?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var isSettled = false
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var settingsObserver: AnyObject?

    private static let settleDelay: Duration = .seconds(4)

    func start() {
        camera.onChange = { [weak self] in self?.update() }
        microphone.onChange = { [weak self] in self?.update() }
        settingsObserver = Defaults.observe(PrivacySettings.observed) { [weak self] in self?.applySettings() }
        applySettings()
    }

    func stop() {
        settingsObserver = nil
        settleTask?.cancel()
        settleTask = nil
        camera.onChange = nil
        microphone.onChange = nil
        camera.stop()
        microphone.stop()
        if shown != nil { ActivityCenter.shared.dismiss(id: PrivacyActivity.id) }
        shown = nil
        sensors = Sensors(camera: false, microphone: false)
    }

    private func applySettings() {
        if Defaults[PrivacySettings.camera] { camera.start() } else { camera.stop() }
        if Defaults[PrivacySettings.microphone] { microphone.start() } else { microphone.stop() }
        update(refresh: true)
    }

    private func update(refresh: Bool = false) {
        let current = Sensors(camera: camera.isActive, microphone: microphone.isActive)
        if sensors != current { sensors = current }

        guard current.any else {
            settleTask?.cancel()
            settleTask = nil
            if shown != nil { ActivityCenter.shared.dismiss(id: PrivacyActivity.id) }
            shown = nil
            return
        }

        if current != shown {
            if shown == nil {
                startedAt = Date()
                if Defaults[PrivacySettings.playSound] {
                    SystemSound.notification.play()
                    Haptics.perform()
                }
            }
            shown = current
            isSettled = false
            present()
            scheduleSettle()
        } else if refresh, ActivityCenter.shared.isPresented(id: PrivacyActivity.id) {
            present()
        }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            // A swipe may have dismissed the indicator; leave it hidden until the sensors change.
            guard !Task.isCancelled, let self, ActivityCenter.shared.isPresented(id: PrivacyActivity.id) else { return }
            self.isSettled = true
            self.present()
        }
    }

    private func present() {
        guard let shown else { return }
        ActivityCenter.shared.present(PrivacyActivity.make(
            sensors: shown,
            startedAt: startedAt,
            showsDuration: Defaults[PrivacySettings.showDuration],
            compact: isSettled && Defaults[PrivacySettings.compactMode],
            settled: isSettled
        ))
    }
}

@MainActor
enum PrivacyActivity {
    static let id = "privacy.indicators"

    private static let dotSize: CGFloat = 6
    private static let dotGap: CGFloat = 4
    private static let groupGap: CGFloat = 7
    private static let cameraSymbolWidth: CGFloat = 18
    private static let micSymbolWidth: CGFloat = 12
    private static let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    private static let timerWidth = ceil(("00:00" as NSString).size(withAttributes: [.font: timerFont]).width) + 2

    static func make(sensors: Sensors, startedAt: Date, showsDuration: Bool, compact: Bool, settled: Bool) -> LiveActivity {
        // Once announced, step below other transient alerts so a long call doesn't hide them.
        let priority: ActivityPriority = settled ? .low : .high

        if compact {
            let count: CGFloat = (sensors.camera ? 1 : 0) + (sensors.microphone ? 1 : 0)
            return LiveActivity(
                id: id,
                category: .other,
                priority: priority,
                duration: nil,
                leadingWidth: count * dotSize + (count - 1) * dotGap,
                trailingWidth: 0,
                leading: {
                    HStack(spacing: dotGap) {
                        if sensors.camera { Dot(color: .green) }
                        if sensors.microphone { Dot(color: .orange) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                },
                trailing: { EmptyView() }
            )
        }

        var leadingWidth: CGFloat = 0
        if sensors.camera { leadingWidth += dotSize + dotGap + cameraSymbolWidth }
        if sensors.microphone { leadingWidth += dotSize + dotGap + micSymbolWidth }
        if sensors.camera && sensors.microphone { leadingWidth += groupGap }

        return LiveActivity(
            id: id,
            category: .other,
            priority: priority,
            duration: nil,
            leadingWidth: leadingWidth,
            trailingWidth: showsDuration ? timerWidth : 0,
            leading: {
                HStack(spacing: groupGap) {
                    if sensors.camera { SensorLabel(color: .green, symbol: "video.fill", width: cameraSymbolWidth) }
                    if sensors.microphone { SensorLabel(color: .orange, symbol: "mic.fill", width: micSymbolWidth) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            },
            trailing: {
                if showsDuration {
                    ElapsedTime(since: startedAt)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        )
    }
}

private struct Dot: View {
    let color: Color

    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

private struct SensorLabel: View {
    let color: Color
    let symbol: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Dot(color: color)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: width)
        }
    }
}

/// Ticks once a second, and only while it is on screen.
private struct ElapsedTime: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            Text(Self.format(context.date.timeIntervalSince(since)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}
