import NotchCore
import SwiftUI

struct MonthGrid: View {
    let manager: CalendarManager
    var cellHeight: CGFloat = 17
    @AppStorage(CalendarSettings.useEventIndicators) private var indicators

    var body: some View {
        let calendar = Calendar.current
        let month = calendar.startOfMonth(for: manager.selectedDay)
        let gridStart = calendar.monthGridStart(for: month)
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = calendar.dateComponents([.day], from: gridStart, to: month).day ?? 0
        let weeks = Int((Double(leading + daysInMonth) / 7).rounded(.up))
        let days = calendar.days(from: gridStart, count: weeks * 7)

        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: cellHeight * 0.8)
            ForEach(0..<weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        cell(day, inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month))
                    }
                }
                .frame(height: cellHeight)
            }
        }
    }

    private func cell(_ day: Date, inMonth: Bool) -> some View {
        let isSelected = day == manager.selectedDay
        let isToday = day == manager.today
        let hasEvents = indicators && manager.hasEvents(on: day)
        return ZStack(alignment: .bottom) {
            Text(day, format: .dateTime.day())
                .font(.system(size: max(8, cellHeight * 0.58), weight: isToday || isSelected ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(
                    isSelected ? (isToday ? .white : .black)
                        : isToday ? .red
                        : .white.opacity(inMonth ? 0.9 : 0.25)
                )
                .frame(width: cellHeight + 1, height: cellHeight)
                .background {
                    Circle().fill(isSelected ? (isToday ? Color.red : .white) : .clear)
                }
            if hasEvents && !isSelected {
                Circle()
                    .fill(.white.opacity(inMonth ? 0.55 : 0.2))
                    .frame(width: 2.5, height: 2.5)
                    .offset(y: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.notchSnappy) { manager.selectedDay = day } }
    }

    private func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
