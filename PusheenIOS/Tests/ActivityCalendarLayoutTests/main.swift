import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
calendar.locale = Locale(identifier: "ru_RU")
let date = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 8, day: 2).date!
let layout = ActivityCalendarLayout(today: date, visibleMonths: 3, calendar: calendar)

expect(layout.columns.count == 9, "June through 2 August 2026 must occupy nine continuous week columns")
expect(layout.columns.allSatisfy { $0.count == 7 }, "Every week column must contain exactly seven aligned rows")

for column in layout.columns {
    for (row, cell) in column.enumerated() {
        let expectedRow = (calendar.component(.weekday, from: cell.date) + 5) % 7
        expect(row == expectedRow, "Every date must stay opposite its Monday-first weekday label")
    }
}

let markers = Dictionary(uniqueKeysWithValues: layout.monthMarkers.map { ($0.label, $0.column) })
expect(markers["июнь"] == 0, "June label must start below June's first calendar column")
expect(markers["июль"] == 4, "July label must start below the column containing 1 July")
expect(markers["авг"] == 8, "August label must start below the column containing 1 August")

let augustFirst = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 8, day: 1).date!
expect(layout.columns[8][5].date == augustFirst, "1 August must be integrated into the common Saturday row")
expect(layout.columns[8][5].isSelectable, "1 August must remain interactive")

let daily = [
    "2026-07-01": 100,
    "2026-08-01": 150,
]
expect(
    ActivityCalendarLayout.monthIncreasePercentage(daily: daily, today: date, calendar: calendar) == 50,
    "Month-over-month increase must be calculated from real activity totals"
)

print("ActivityCalendarLayout tests passed")
