import NotchCore
import SwiftUI

struct CalendarWidget: View {
    var forceMonthView = false

    private let manager = CalendarManager.shared
    @AppStorage(CalendarSettings.alwaysShowMonthView) private var monthSetting

    private var monthView: Bool { forceMonthView || monthSetting }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Group {
                if manager.authorization != .granted {
                    CalendarAccessPrompt(manager: manager)
                } else if size.width >= 430 {
                    wide(size)
                } else if monthView {
                    narrowMonth(size)
                } else {
                    narrowWeek
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .onAppear { manager.revalidate() }
    }

    private func wide(_ size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: monthView ? 4 : 0) {
                CalendarHeader(manager: manager, monthMode: monthView, large: !monthView)
                if !monthView {
                    Text(daySummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
                if monthView {
                    MonthGrid(manager: manager, cellHeight: min(19, (size.height - 34) / 7))
                } else {
                    Spacer(minLength: 6)
                    WeekStrip(manager: manager)
                }
            }
            .frame(width: monthView ? 210 : 240)
            .frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1).padding(.vertical, 4)
            EventList(manager: manager)
        }
    }

    private var daySummary: String {
        let day = manager.selectedDay
        let events = manager.events(on: day)
        guard day == manager.today else {
            return events.isEmpty ? "No events" : events.count == 1 ? "1 event" : "\(events.count) events"
        }
        let remaining = events.filter { !$0.hasEnded(at: manager.now) }.count
        switch remaining {
        case 0: return events.isEmpty ? "No events today" : "No more events today"
        case 1: return "1 event left today"
        default: return "\(remaining) events left today"
        }
    }

    private func narrowMonth(_ size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                CalendarHeader(manager: manager, monthMode: true)
                MonthGrid(manager: manager, cellHeight: min(17, (size.height - 30) / 7))
            }
            .frame(width: min(140, size.width * 0.48))
            EventList(manager: manager)
        }
    }

    private var narrowWeek: some View {
        VStack(alignment: .leading, spacing: 4) {
            CalendarHeader(manager: manager, monthMode: false)
            WeekStrip(manager: manager)
            EventList(manager: manager)
        }
    }
}

struct EventList: View {
    let manager: CalendarManager
    var maxTimedEvents = 8

    @AppStorage(CalendarSettings.useCalendarColor) private var useCalendarColor
    @AppStorage(CalendarSettings.showWeatherOnEmptyDay) private var showWeather
    @State private var expandAllDay = false

    var body: some View {
        let day = manager.selectedDay
        let now = manager.now
        let isToday = day == manager.today
        let all = manager.events(on: day)
        let allDay = all.filter(\.isAllDay)
        let timed = all.filter { !$0.isAllDay && !(isToday && $0.hasEnded(at: now)) }

        Group {
            if !timed.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        allDaySection(allDay)
                        eventRows(timed, now: now)
                    }
                }
                .scrollIndicators(.never)
            } else if isToday {
                let title = all.contains(where: { !$0.isAllDay }) ? "No more events today" : "No events today"
                let tomorrow = manager.events(on: manager.tomorrow)
                if tomorrow.isEmpty {
                    emptyState(title: title, subtitle: "Your day is clear", allDay: allDay, weather: true)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                            allDaySection(allDay)
                            sectionHeader("Tomorrow")
                            tomorrowRows(tomorrow, now: now)
                        }
                    }
                    .scrollIndicators(.never)
                }
            } else {
                emptyState(title: "No events", subtitle: "This day is clear", allDay: allDay, weather: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: day) { expandAllDay = false }
    }

    @ViewBuilder
    private func allDaySection(_ events: [CalendarEvent]) -> some View {
        if !events.isEmpty {
            if expandAllDay || events.count == 1 {
                ForEach(events) { row($0, now: manager.now) }
                if events.count > 1 {
                    SummaryRow(symbol: "chevron.up", text: "Hide all-day") {
                        withAnimation(.notchSnappy) { expandAllDay = false }
                    }
                }
            } else {
                SummaryRow(symbol: "sun.max.fill", text: "+\(events.count) all-day", trailingSymbol: "chevron.down") {
                    withAnimation(.notchSnappy) { expandAllDay = true }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRows(_ events: [CalendarEvent], now: Date) -> some View {
        ForEach(events.prefix(maxTimedEvents)) { row($0, now: now) }
        if events.count > maxTimedEvents {
            SummaryRow(symbol: "ellipsis", text: "\(events.count - maxTimedEvents) more events", trailingSymbol: "arrow.up.right") {
                CalendarManager.openCalendarApp()
            }
        }
    }

    @ViewBuilder
    private func tomorrowRows(_ events: [CalendarEvent], now: Date) -> some View {
        let allDay = events.filter(\.isAllDay)
        let timed = events.filter { !$0.isAllDay }
        if allDay.count == 1 {
            row(allDay[0], now: now)
        } else if !allDay.isEmpty {
            SummaryRow(symbol: "sun.max.fill", text: "+\(allDay.count) all-day") {
                withAnimation(.notchSnappy) { manager.selectedDay = manager.tomorrow }
            }
        }
        eventRows(timed, now: now)
    }

    private func row(_ event: CalendarEvent, now: Date) -> some View {
        EventRow(
            event: event,
            now: now,
            useCalendarColor: useCalendarColor,
            isDismissed: manager.isDismissed(event),
            manager: manager
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .frame(height: 18, alignment: .bottom)
    }

    @ViewBuilder
    private func emptyState(title: String, subtitle: String, allDay: [CalendarEvent], weather: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            allDaySection(allDay)
            EmptyDayView(
                title: title,
                subtitle: subtitle,
                weather: weather && showWeather ? SystemStatus.shared.weather : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct EmptyDayView: View {
    let title: String
    let subtitle: String
    let weather: WeatherSnapshot?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                if let weather { WeatherBadge(weather: weather) }
                labels(alignment: weather == nil ? .center : .leading)
            }
            VStack(spacing: 6) {
                if let weather { WeatherBadge(weather: weather) }
                labels(alignment: .center)
            }
        }
    }

    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if weather == nil {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 4)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct WeatherBadge: View {
    let weather: WeatherSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: weather.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Self.degrees(weather.temperature))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("H:\(Self.degrees(weather.high)) L:\(Self.degrees(weather.low))")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .fixedSize()
        .help(weather.conditionName)
    }

    private static func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}

struct CalendarAccessPrompt: View {
    let manager: CalendarManager

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.6))
            Text(manager.authorization == .denied ? "Calendar access is turned off" : "See your upcoming events here")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Button {
                Task { await manager.requestAccess() }
            } label: {
                Text("Allow Calendar Access")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
