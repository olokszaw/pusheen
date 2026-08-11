import Foundation

struct ActivityCalendarLayout {
    struct Cell: Identifiable, Equatable {
        let date: Date
        let isSelectable: Bool

        var id: Date { date }
    }

    struct MonthMarker: Equatable {
        let monthStart: Date
        let label: String
        let column: Int
    }

    let columns: [[Cell]]
    let monthMarkers: [MonthMarker]
    let displayedDays: [Date]

    init(
        today inputToday: Date,
        visibleMonths: Int,
        calendar inputCalendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ru_RU")
    ) {
        var calendar = inputCalendar
        calendar.locale = locale
        let today = calendar.startOfDay(for: inputToday)
        let safeMonthCount = max(1, visibleMonths)
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today
        let firstMonthStart = calendar.date(
            byAdding: .month,
            value: -(safeMonthCount - 1),
            to: currentMonthStart
        ) ?? currentMonthStart

        let gridStart = calendar.date(
            byAdding: .day,
            value: -Self.mondayRow(for: firstMonthStart, calendar: calendar),
            to: firstMonthStart
        ) ?? firstMonthStart
        let gridEnd = calendar.date(
            byAdding: .day,
            value: 6 - Self.mondayRow(for: today, calendar: calendar),
            to: today
        ) ?? today
        let totalDays = max(
            7,
            (calendar.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 6) + 1
        )
        let columnCount = max(1, Int(ceil(Double(totalDays) / 7.0)))

        columns = (0..<columnCount).map { column in
            (0..<7).compactMap { row in
                guard let date = calendar.date(
                    byAdding: .day,
                    value: column * 7 + row,
                    to: gridStart
                ) else { return nil }
                return Cell(
                    date: date,
                    isSelectable: date >= firstMonthStart && date <= today
                )
            }
        }

        displayedDays = columns
            .flatMap { $0 }
            .filter(\.isSelectable)
            .map(\.date)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.dateFormat = "LLL"
        monthMarkers = (0..<safeMonthCount).compactMap { offset in
            guard let monthStart = calendar.date(
                byAdding: .month,
                value: offset,
                to: firstMonthStart
            ) else { return nil }
            let dayOffset = calendar.dateComponents(
                [.day],
                from: gridStart,
                to: monthStart
            ).day ?? 0
            return MonthMarker(
                monthStart: monthStart,
                label: formatter.string(from: monthStart).replacingOccurrences(of: ".", with: ""),
                column: max(0, dayOffset / 7)
            )
        }
    }

    static func monthIncreasePercentage(
        daily: [String: Int],
        today inputToday: Date,
        calendar inputCalendar: Calendar = .current
    ) -> Int {
        let calendar = inputCalendar
        let today = calendar.startOfDay(for: inputToday)
        let currentStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) ?? today
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        let current = sum(daily: daily, from: currentStart, through: today, calendar: calendar)
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart) ?? previousStart
        let elapsedDays = calendar.dateComponents([.day], from: currentStart, to: today).day ?? 0
        let comparablePreviousEnd = min(
            calendar.date(byAdding: .day, value: elapsedDays, to: previousStart) ?? previousEnd,
            previousEnd
        )
        let previous = sum(daily: daily, from: previousStart, through: comparablePreviousEnd, calendar: calendar)

        guard previous > 0 else { return current > 0 ? 100 : 0 }
        let change = ((Double(current) - Double(previous)) / Double(previous)) * 100
        return max(0, Int(change.rounded()))
    }

    static func dayKey(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    private static func mondayRow(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private static func sum(
        daily: [String: Int],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> Int {
        guard start <= end else { return 0 }
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return (0..<count).reduce(0) { total, offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return total }
            return total + (daily[dayKey(for: day, calendar: calendar)] ?? 0)
        }
    }
}
