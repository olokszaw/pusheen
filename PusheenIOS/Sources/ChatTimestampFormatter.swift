import Foundation

enum ChatTimestampFormatter {
    static func date(from rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: rawValue)
    }

    static func string(
        from rawValue: String?,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = date(from: rawValue) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum PresenceTimestampFormatter {
    /// The backend already applies the heartbeat TTL when it builds
    /// `is_online`. Repeating that decision against the phone clock caused a
    /// valid server `true` to become offline when the device and server clocks
    /// (or their configured time zones) did not match exactly.
    static func isOnline(isOnline: Bool?, visible: Bool?) -> Bool {
        visible != false && isOnline == true
    }

    static func string(
        isOnline: Bool?,
        lastSeen: String?,
        visible: Bool?,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        if visible == false { return "Активность скрыта" }
        if self.isOnline(isOnline: isOnline, visible: visible) { return "Онлайн" }
        guard let date = ChatTimestampFormatter.date(from: lastSeen) else {
            return "Был(а) недавно"
        }

        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 2 { return "Был(а) недавно" }
        if minutes < 60 { return "Был(а) \(minutes) мин. назад" }
        let hours = minutes / 60
        if hours < 6 { return "Был(а) \(hours) ч. назад" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.timeStyle = .short
        time.dateStyle = .none

        if calendar.isDateInToday(date) {
            return "Был(а) сегодня в \(time.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Был(а) вчера в \(time.string(from: date))"
        }

        let full = DateFormatter()
        full.locale = locale
        full.timeZone = timeZone
        full.setLocalizedDateFormatFromTemplate("dMMMjm")
        return "Был(а) \(full.string(from: date))"
    }
}
