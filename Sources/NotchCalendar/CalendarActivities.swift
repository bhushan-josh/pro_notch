import NotchCore
import Observation
import SwiftUI

enum CalendarActivityID {
    static let idle = "calendar.idle"
    static let chime = "calendar.chime"

    static func upcoming(_ event: CalendarEvent) -> String { "calendar.upcoming.\(event.id)" }
    static func starting(_ event: CalendarEvent) -> String { "calendar.start.\(event.id)" }
    static func leave(_ event: CalendarEvent) -> String { "calendar.leave.\(event.id)" }

    static func all(for event: CalendarEvent) -> [String] {
        [upcoming(event), starting(event), leave(event)]
    }
}

/// Upcoming / starting alerts, the hourly chime and the low-key idle activity for the closed notch.
@MainActor
@Observable
final class CalendarActivities: IdleActivityProvider {
    private(set) var idleActivity: LiveActivity?
    private(set) var idleActivityUpdatedAt = Date.distantPast

    @ObservationIgnored private let manager: CalendarManager
    @ObservationIgnored private var idleKey: String?
    @ObservationIgnored private var idleText: String?
    @ObservationIgnored private var notifiedUpcoming: Set<String> = []
    @ObservationIgnored private var notifiedStart: Set<String> = []
    @ObservationIgnored private var lastChimeHour: Date?

    init(manager: CalendarManager) {
        self.manager = manager
    }

    private var leadTime: TimeInterval { TimeInterval(max(1, Defaults[CalendarSettings.timeBeforeEvent])) * 60 }

    func update() {
        let now = Date()
        guard Defaults[CalendarSettings.enabled] else {
            setIdle(nil, key: nil, text: nil)
            return
        }
        chimeIfNeeded(now)
        let events = manager.upcomingTimedEvents.filter { !manager.isDismissed($0) }
        let ids = Set(events.map(\.id))
        notifiedUpcoming.formIntersection(ids)
        notifiedStart.formIntersection(ids)
        notify(events, now: now)
        updateIdle(events, now: now)
    }

    func stop() {
        setIdle(nil, key: nil, text: nil)
        ActivityCenter.shared.dismiss(category: .calendar)
    }

    // MARK: Alerts

    private func notify(_ events: [CalendarEvent], now: Date) {
        let lead = leadTime
        for event in events {
            let until = event.start.timeIntervalSince(now)
            if Defaults[CalendarSettings.notifyBeforeEvent], until > 30, until <= lead + 5,
               notifiedUpcoming.insert(event.id).inserted {
                present(event, id: CalendarActivityID.upcoming(event), trailing: EventFormat.countdown(to: event.start, from: now))
            }
            if Defaults[CalendarSettings.notifyWhenEventStarts], until <= 5, until > -120,
               notifiedStart.insert(event.id).inserted {
                notifiedUpcoming.insert(event.id)
                ActivityCenter.shared.dismiss(id: CalendarActivityID.upcoming(event))
                present(event, id: CalendarActivityID.starting(event), trailing: "Now")
            }
        }
    }

    private func present(_ event: CalendarEvent, id: String, trailing: String) {
        let colored = Defaults[CalendarSettings.useColoredCalendarIndicator]
        let activity = LiveActivity(
            id: id,
            category: .calendar,
            priority: .normal,
            duration: 6,
            leadingWidth: 24,
            trailingWidth: 54,
            leading: { EventIndicator(color: event.calendarColor, colored: colored, size: 9) },
            trailing: {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(colored ? event.calendarColor : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            },
            onTap: { CalendarManager.join(event) }
        )
        .withBottom(height: 24) {
            HStack(spacing: 6) {
                if let meeting = event.meeting {
                    Image(systemName: meeting.provider.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                MarqueeText(event.title, font: .system(size: 12, weight: .semibold))
            }
        }
        ActivityCenter.shared.present(activity)
        if Defaults[CalendarSettings.playSoundOnEvent] { SystemSound.event.play() }
    }

    // MARK: Idle

    private func updateIdle(_ events: [CalendarEvent], now: Date) {
        let lead = leadTime
        let soon = events.first { event in
            let until = event.start.timeIntervalSince(now)
            return until > 0 && until <= lead
        }
        let ongoing = Defaults[CalendarSettings.disableActivityDuringEvents]
            ? nil
            : events.last { $0.isInProgress(at: now) }
        guard let event = soon ?? ongoing else {
            setIdle(nil, key: nil, text: nil)
            return
        }
        let inProgress = event.isInProgress(at: now)
        let trailing = inProgress
            ? "ends \(EventFormat.shortTime(event.end))"
            : EventFormat.countdown(to: event.start, from: now)
        let key = "\(event.id)|\(inProgress)"
        let colored = Defaults[CalendarSettings.useColoredCalendarIndicator]
        let text = "\(trailing)|\(event.title)|\(colored)"
        guard key != idleKey || text != idleText else { return }
        let activity = LiveActivity(
            id: CalendarActivityID.idle,
            category: .calendar,
            priority: .idle,
            leadingWidth: 86,
            trailingWidth: 62,
            leading: {
                HStack(spacing: 5) {
                    EventIndicator(color: event.calendarColor, colored: colored, size: 7)
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            trailing: {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        )
        setIdle(activity, key: key, text: text)
    }

    private func setIdle(_ activity: LiveActivity?, key: String?, text: String?) {
        if activity == nil && idleActivity == nil { return }
        if key != idleKey { idleActivityUpdatedAt = Date() }
        idleKey = key
        idleText = text
        idleActivity = activity
    }

    // MARK: Chime

    private func chimeIfNeeded(_ now: Date) {
        guard Defaults[CalendarSettings.playHourlyChime] else { return }
        let calendar = Calendar.current
        guard calendar.component(.minute, from: now) == 0,
              let hour = calendar.dateInterval(of: .hour, for: now)?.start,
              hour != lastChimeHour else { return }
        lastChimeHour = hour
        SystemSound.chime.play()
        ActivityCenter.shared.present(LiveActivity(
            id: CalendarActivityID.chime,
            category: .calendar,
            priority: .low,
            duration: 3,
            leadingWidth: 24,
            trailingWidth: 54,
            leading: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.yellow)
            },
            trailing: {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        ))
    }
}

struct EventIndicator: View {
    let color: Color
    let colored: Bool
    var size: CGFloat = 8

    var body: some View {
        if colored {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 3)
        } else {
            Image(systemName: "calendar")
                .font(.system(size: size + 4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
