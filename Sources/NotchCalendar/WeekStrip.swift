import NotchCore
import SwiftUI

struct CalendarHeader: View {
    let manager: CalendarManager
    let monthMode: Bool
    var large = false

    var body: some View {
        let day = manager.selectedDay
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button { select(manager.today) } label: {
                if monthMode {
                    Text(day, format: .dateTime.month(.wide).year())
                        .font(.system(size: large ? 15 : 13, weight: .bold))
                        .lineLimit(1)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(day, format: .dateTime.weekday(.wide))
                            .font(.system(size: large ? 18 : 13, weight: .bold))
                            .foregroundStyle(day == manager.today ? .red : .white)
                        Text(day, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: large ? 14 : 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("Go to Today")
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                stepButton("chevron.left", by: -1)
                stepButton("chevron.right", by: 1)
            }
        }
        .minimumScaleFactor(0.8)
    }

    private func stepButton(_ symbol: String, by delta: Int) -> some View {
        Button {
            let calendar = Calendar.current
            let target = monthMode
                ? calendar.date(byAdding: .month, value: delta, to: calendar.startOfMonth(for: manager.selectedDay))
                : calendar.date(byAdding: .day, value: delta * 7, to: manager.selectedDay)
            guard let target else { return }
            let sameMonth = calendar.isDate(target, equalTo: manager.today, toGranularity: .month)
            select(monthMode && sameMonth ? manager.today : target)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ day: Date) {
        withAnimation(.notchSnappy) { manager.selectedDay = day }
    }
}

struct WeekStrip: View {
    let manager: CalendarManager
    @AppStorage(CalendarSettings.useEventIndicators) private var indicators

    var body: some View {
        let calendar = Calendar.current
        let days = calendar.days(from: calendar.startOfWeek(for: manager.selectedDay), count: 7)
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    day: day,
                    isSelected: day == manager.selectedDay,
                    isToday: day == manager.today,
                    hasEvents: indicators && manager.hasEvents(on: day)
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.notchSnappy) { manager.selectedDay = day } }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let hasEvents: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(day, format: .dateTime.day())
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(isSelected ? (isToday ? Color.red : .white) : .clear)
                }
                .foregroundStyle(isSelected && isToday ? .white : isSelected ? .black : isToday ? .red : .white)
            Circle()
                .fill(.white.opacity(hasEvents ? 0.6 : 0))
                .frame(width: 4, height: 4)
        }
    }
}
