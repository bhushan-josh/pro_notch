import Foundation
import NotchCore
import Observation

enum TimerPhase: String, Codable, Sendable {
    case idle, running, paused, finished
}

/// One countdown timer. Running time is kept as an end date so it stays correct across sleep and relaunch.
@MainActor
@Observable
final class TimerManager {
    static let maxDuration: TimeInterval = 99 * 3600 + 59 * 60 + 59
    static let alertDuration: TimeInterval = 30

    private(set) var phase = TimerPhase.idle
    /// Total length including any minutes added while running; the progress ring is measured against it.
    private(set) var duration: TimeInterval = 0
    /// Length the timer was started with, reused by Repeat.
    private(set) var initialDuration: TimeInterval = 0
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval = 0
    /// Preset lengths in minutes, mirrored from settings so the page re-renders when they change.
    var presets = TimersSettings.presetMinutes

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var ringTask: Task<Void, Never>?
    @ObservationIgnored private var alertActivityID: String?

    private static let storageKey = "timers.saved"

    var isActive: Bool { phase == .running || phase == .paused }

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch phase {
        case .running: max(0, (endDate ?? date).timeIntervalSince(date))
        case .paused: pausedRemaining
        case .idle, .finished: 0
        }
    }

    /// Fraction of the timer still left, 1 at the start and 0 when done.
    func remainingFraction(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(remaining(at: date) / duration, 0), 1)
    }

    // MARK: Controls

    func start(_ seconds: TimeInterval) {
        let seconds = min(max(seconds.rounded(), 1), Self.maxDuration)
        stopRinging()
        duration = seconds
        initialDuration = seconds
        pausedRemaining = 0
        endDate = Date().addingTimeInterval(seconds)
        phase = .running
        changed()
    }

    func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining()
        endDate = nil
        phase = .paused
        changed()
    }

    func resume() {
        guard phase == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        pausedRemaining = 0
        phase = .running
        changed()
    }

    func togglePause() { phase == .running ? pause() : resume() }

    func addMinute() {
        switch phase {
        case .running:
            guard let endDate, remaining() + 60 <= Self.maxDuration else { return }
            self.endDate = endDate.addingTimeInterval(60)
        case .paused:
            guard pausedRemaining + 60 <= Self.maxDuration else { return }
            pausedRemaining += 60
        case .idle, .finished:
            return
        }
        duration += 60
        changed()
    }

    func cancel() {
        guard phase != .idle else { return }
        stopRinging()
        reset()
        changed()
    }

    /// Stops the finished alert and returns to idle.
    func dismissAlert() {
        guard phase == .finished else { return }
        stopRinging()
        reset()
        changed()
    }

    func repeatLast() {
        let seconds = initialDuration > 0 ? initialDuration : duration
        guard seconds > 0 else { return }
        start(seconds)
    }

    private func reset() {
        phase = .idle
        endDate = nil
        pausedRemaining = 0
        duration = 0
    }

    private func finish() {
        guard phase == .running else { return }
        endDate = nil
        pausedRemaining = 0
        phase = .finished
        changed()
        onFinish?()
    }

    // MARK: Deadline

    private func changed() {
        scheduleFinish()
        save()
        onChange?()
    }

    private func scheduleFinish() {
        finishTask?.cancel()
        finishTask = nil
        guard phase == .running, let end = endDate else { return }
        finishTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            // The default clock is continuous, so the deadline keeps counting through system sleep.
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, self.phase == .running, self.endDate == end else { return }
            self.finish()
        }
    }

    /// Called after wake: finishes a timer that ran out while asleep, otherwise re-arms the deadline.
    func revalidate() {
        guard phase == .running, let endDate else { return }
        if endDate <= Date() { finish() } else { scheduleFinish() }
    }

    func suspend() {
        finishTask?.cancel()
        finishTask = nil
        stopRinging()
    }

    // MARK: Alert sound

    /// Plays the alert sound, repeating every few seconds if asked, and dismisses the alert after
    /// `alertDuration` or as soon as its activity is swiped away.
    func ring(activityID: String) {
        stopRinging()
        alertActivityID = activityID
        let sound = Defaults[TimersSettings.sound].systemSound
        let repeats = Defaults[TimersSettings.repeatSound]
        ringTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(Self.alertDuration)
            var playsSound = true
            while Date() < deadline {
                if playsSound { sound.play(volume: 0.8) }
                playsSound = repeats
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                if !ActivityCenter.shared.isPresented(id: activityID) { break }
            }
            self?.dismissAlert()
        }
    }

    private func stopRinging() {
        ringTask?.cancel()
        ringTask = nil
        if let alertActivityID { ActivityCenter.shared.dismiss(id: alertActivityID) }
        alertActivityID = nil
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var phase: TimerPhase
        var duration: TimeInterval
        var initialDuration: TimeInterval
        var endDate: Date?
        var pausedRemaining: TimeInterval
    }

    private func save() {
        let store = Defaults.store
        guard isActive else {
            store.removeObject(forKey: Self.storageKey)
            return
        }
        let saved = Saved(phase: phase, duration: duration, initialDuration: initialDuration, endDate: endDate, pausedRemaining: pausedRemaining)
        if let data = try? JSONEncoder().encode(saved) { store.set(data, forKey: Self.storageKey) }
    }

    /// Restores a timer saved before quitting. One that ran out while the app was closed still alerts
    /// if it ended in the last few minutes, otherwise it is dropped silently.
    func restore() {
        guard let data = Defaults.store.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        duration = saved.duration
        initialDuration = saved.initialDuration
        switch saved.phase {
        case .running:
            guard let end = saved.endDate else { return cancelRestored() }
            if end > Date() {
                endDate = end
                phase = .running
                changed()
            } else if Date().timeIntervalSince(end) < 300 {
                endDate = end
                phase = .running
                finish()
            } else {
                cancelRestored()
            }
        case .paused:
            pausedRemaining = saved.pausedRemaining
            phase = .paused
            changed()
        case .idle, .finished:
            cancelRestored()
        }
    }

    private func cancelRestored() {
        reset()
        save()
    }
}

enum TimerFormat {
    /// "m:ss" or "h:mm:ss". Rounds up so a fresh 5 minute timer reads 5:00 and the last second reads 0:01.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int((seconds - 0.001).rounded(.up)))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "45 sec", "5 min", "1 hr 30 min".
    static func length(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hr") }
        if m > 0 { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sec") }
        return parts.joined(separator: " ")
    }

    /// Big number and unit for a preset chip: ("25", "min"), ("1", "hr"), ("1:30", "hr").
    static func preset(_ minutes: Int) -> (value: String, unit: String) {
        if minutes < 60 { return ("\(minutes)", "min") }
        if minutes % 60 == 0 { return ("\(minutes / 60)", "hr") }
        return (String(format: "%d:%02d", minutes / 60, minutes % 60), "hr")
    }
}
