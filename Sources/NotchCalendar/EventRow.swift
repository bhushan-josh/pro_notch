import NotchCore
import SwiftUI

struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let useCalendarColor: Bool
    let isDismissed: Bool
    let manager: CalendarManager

    var body: some View {
        let inProgress = event.isInProgress(at: now)
        let color = event.color(useCalendarColor: useCalendarColor)
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                detailLine(inProgress: inProgress)
            }
            .layoutPriority(1)
            Spacer(minLength: 2)
            if showsJoin(inProgress: inProgress) {
                Button { CalendarManager.join(event) } label: {
                    Text("Join")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(useCalendarColor ? event.calendarColor : .white, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Join \(event.meeting?.provider.title ?? "Meeting")")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(.white.opacity(inProgress ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isDismissed ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { CalendarManager.open(event) }
        .contextMenu { EventContextMenu(event: event, isDismissed: isDismissed, manager: manager) }
    }

    private func showsJoin(inProgress: Bool) -> Bool {
        guard event.meeting != nil, !event.isAllDay else { return false }
        return inProgress || (event.start > now && event.start.timeIntervalSince(now) <= 15 * 60)
    }

    @ViewBuilder
    private func detailLine(inProgress: Bool) -> some View {
        HStack(spacing: 4) {
            Text(timeText(inProgress: inProgress))
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)
            if let meeting = event.meeting {
                Image(systemName: meeting.provider.symbol)
                    .font(.system(size: 8, weight: .semibold))
                Text(meeting.provider.title).lineLimit(1)
            } else if let location = event.location {
                Image(systemName: "location.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                Text(location).lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
    }

    private func timeText(inProgress: Bool) -> String {
        if event.isAllDay { return "All day" }
        if inProgress { return "Now, until \(EventFormat.time(event.end))" }
        let until = event.start.timeIntervalSince(now)
        if until > 0 && until <= 60 * 60 {
            return "\(EventFormat.time(event.start)), \(EventFormat.countdown(to: event.start, from: now))"
        }
        return EventFormat.timeRange(event)
    }
}

struct EventContextMenu: View {
    let event: CalendarEvent
    let isDismissed: Bool
    let manager: CalendarManager

    var body: some View {
        if let meeting = event.meeting {
            Button("Join", systemImage: "video.fill") { CalendarManager.join(event) }
                .help(meeting.provider.title)
        }
        Button("Open in Calendar", systemImage: "calendar") { CalendarManager.open(event) }
        Divider()
        if isDismissed {
            Button("Restore Event", systemImage: "arrow.uturn.backward") { manager.restore(event) }
        } else {
            Button("Dismiss Event", systemImage: "xmark.circle") { manager.dismiss(event) }
        }
    }
}

/// "+3 all-day", "4 more events" and similar summary rows.
struct SummaryRow: View {
    let symbol: String
    let text: String
    var trailingSymbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
