import AppKit
import EventKit
import SwiftUI

struct EventCoordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct CalendarEvent: Identifiable, Equatable {
    /// Unique per occurrence; `eventIdentifier` is shared by every occurrence of a recurring event.
    let id: String
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let calendarColor: Color
    let location: String?
    let coordinate: EventCoordinate?
    let meeting: MeetingLink?

    init(_ event: EKEvent) {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let start = event.startDate ?? Date()
        id = "\(identifier)@\(Int(start.timeIntervalSince1970))"
        eventIdentifier = identifier
        let rawTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = rawTitle.isEmpty ? "New Event" : rawTitle
        self.start = start
        end = event.endDate ?? start
        isAllDay = event.isAllDay
        calendarID = event.calendar?.calendarIdentifier ?? ""
        calendarTitle = event.calendar?.title ?? ""
        calendarColor = event.calendar?.color.map { Color(nsColor: $0) } ?? .red
        let trimmedLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        location = trimmedLocation?.isEmpty == false ? trimmedLocation : nil
        coordinate = event.structuredLocation?.geoLocation.map {
            EventCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        meeting = MeetingLinks.detect(url: event.url, location: event.location, notes: event.notes)
    }

    func isInProgress(at date: Date) -> Bool { start <= date && date < end }
    func hasEnded(at date: Date) -> Bool { end <= date }

    func color(useCalendarColor: Bool) -> Color { useCalendarColor ? calendarColor : .white }

    /// A physical place worth travelling to, as opposed to a video link pasted into the location field.
    var travelDestination: String? {
        guard let location, MeetingLinks.detect(url: nil, location: location, notes: nil) == nil,
              !location.lowercased().hasPrefix("http") else { return nil }
        return location
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }

    func monthGridStart(for date: Date) -> Date {
        startOfWeek(for: startOfMonth(for: date))
    }

    func days(from start: Date, count: Int) -> [Date] {
        (0..<count).compactMap { date(byAdding: .day, value: $0, to: start) }
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }
}

enum EventFormat {
    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
    }

    static func timeRange(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        return "\(time(event.start)) - \(time(event.end))"
    }

    /// "in 5m", "in 1h 20m", "now".
    static func countdown(to date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "in \(hours)h" : "in \(hours)h \(rest)m"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }
}
