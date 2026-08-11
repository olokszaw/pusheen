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

let partialMonthDate = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 8, day: 11).date!
let partialMonthDaily = [
    "2026-07-01": 50,
    "2026-07-20": 10_000,
    "2026-08-01": 100,
]
expect(
    ActivityCalendarLayout.monthIncreasePercentage(daily: partialMonthDaily, today: partialMonthDate, calendar: calendar) == 100,
    "An unfinished month must be compared with the same elapsed days of the previous month"
)

let timestamp = "2026-08-02T16:05:00.000Z"
let utc = TimeZone(secondsFromGMT: 0)!
let russianTime = ChatTimestampFormatter.string(
    from: timestamp,
    locale: Locale(identifier: "ru_RU"),
    timeZone: utc
)
let americanTime = ChatTimestampFormatter.string(
    from: timestamp,
    locale: Locale(identifier: "en_US"),
    timeZone: utc
)
expect(russianTime.contains("16:05"), "24-hour locales must receive 24-hour message times")
expect(americanTime.contains("4:05") && americanTime.uppercased().contains("PM"), "12-hour locales must receive AM/PM message times")

let utcTimestamp = "2026-08-11T14:42:00.000Z"
let utcPlusSeven = TimeZone(secondsFromGMT: 7 * 3_600)!
let laterNow = ISO8601DateFormatter().date(from: "2026-08-11T20:50:00Z")!
let localizedPresence = PresenceTimestampFormatter.string(
    isOnline: false,
    lastSeen: utcTimestamp,
    visible: true,
    now: laterNow,
    locale: Locale(identifier: "ru_RU"),
    timeZone: utcPlusSeven
)
expect(
    localizedPresence.contains("21:42") && !localizedPresence.contains("14:42"),
    "Presence timestamps must be rendered in the phone time zone instead of raw UTC"
)
let phoneNow = ISO8601DateFormatter().date(from: "2026-08-11T14:42:00Z")!
let serverClockIndependentPresence = PresenceTimestampFormatter.string(
    isOnline: false,
    lastSeen: "2026-08-11T02:42:00.000Z",
    lastSeenAgeSeconds: 6 * 3_600,
    ageAnchor: phoneNow,
    visible: true,
    now: phoneNow,
    locale: Locale(identifier: "ru_RU"),
    timeZone: utcPlusSeven
)
expect(
    serverClockIndependentPresence.contains("15:42")
        && !serverClockIndependentPresence.contains("09:42"),
    "Presence must anchor elapsed time to the iPhone clock instead of the server wall clock"
)
expect(
    PresenceTimestampFormatter.isOnline(isOnline: true, visible: true),
    "The client must trust the backend heartbeat decision instead of rejecting it using a different clock"
)
expect(
    PresenceTimestampFormatter.string(
        isOnline: true,
        lastSeen: "2026-08-11T00:00:00Z",
        visible: true,
        now: laterNow,
        locale: Locale(identifier: "ru_RU"),
        timeZone: utcPlusSeven
    ) == "Онлайн",
    "A server-authoritative online status must survive device/server clock skew"
)

let presenceAnchor = ISO8601DateFormatter().date(from: "2026-08-11T16:00:00Z")!
expect(
    PresenceTimestampFormatter.string(
        isOnline: false,
        lastSeen: nil,
        lastSeenAgeSeconds: 4 * 60,
        ageAnchor: presenceAnchor,
        visible: true,
        now: presenceAnchor,
        locale: Locale(identifier: "ru_RU"),
        timeZone: utc
    ) == "Был(а) 4 мин. назад",
    "The first five offline minutes must use relative minutes"
)
expect(
    PresenceTimestampFormatter.string(
        isOnline: false,
        lastSeen: nil,
        lastSeenAgeSeconds: 5 * 60,
        ageAnchor: presenceAnchor,
        visible: true,
        now: presenceAnchor,
        locale: Locale(identifier: "ru_RU"),
        timeZone: utc
    ).contains("15:55"),
    "At five minutes offline the UI must switch to the phone-local clock time"
)
expect(
    PresenceTimestampFormatter.string(
        isOnline: false,
        lastSeen: nil,
        lastSeenAgeSeconds: nil,
        ageAnchor: presenceAnchor,
        visible: true,
        now: presenceAnchor,
        locale: Locale(identifier: "ru_RU"),
        timeZone: utc
    ) == "Не в сети",
    "Missing presence data must never display the vague recently label"
)

let messageJSON = """
{"id":1,"author_id":7,"nickname":"Test","text":"Hi","image_data_url":"","avatar_data_url":"","reactions":[],"created_at":"2026-08-02T16:05:00Z"}
""".data(using: .utf8)!
let decodedMessage = try JSONDecoder().decode(ChatMessage.self, from: messageJSON)
expect(decodedMessage.createdAt == "2026-08-02T16:05:00Z", "Chat messages must decode the server creation timestamp")

print("ActivityCalendarLayout tests passed")
