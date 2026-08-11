import Foundation

enum ChatTimestampFormatter {
    static func resolvedDate(
        from rawValue: String?,
        ageSeconds: Int? = nil,
        ageAnchor: Date? = nil,
        now: Date = Date()
    ) -> Date? {
        if let ageSeconds {
            return (ageAnchor ?? now).addingTimeInterval(-Double(max(0, ageSeconds)))
        }
        return date(from: rawValue)
    }

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
        ageSeconds: Int? = nil,
        ageAnchor: Date? = nil,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date = resolvedDate(
            from: rawValue,
            ageSeconds: ageSeconds,
            ageAnchor: ageAnchor,
            now: now
        ) else { return "" }
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
        lastSeenAgeSeconds: Int? = nil,
        ageAnchor: Date? = nil,
        visible: Bool?,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        if visible == false { return "Активность скрыта" }
        if self.isOnline(isOnline: isOnline, visible: visible) { return "Онлайн" }
        // Prefer elapsed time from the backend and anchor it to this iPhone's
        // own clock. The raw ISO timestamp remains only as compatibility with
        // older servers. This prevents a wrong Windows wall clock from
        // changing the hour displayed on every phone.
        let date: Date?
        if let lastSeenAgeSeconds {
            date = (ageAnchor ?? now).addingTimeInterval(-Double(max(0, lastSeenAgeSeconds)))
        } else {
            date = ChatTimestampFormatter.date(from: lastSeen)
        }
        // Never show the vague "recently" state. If an old backend cannot
        // provide a timestamp, an explicit offline label is more truthful.
        guard let date else { return "Не в сети" }

        let elapsedSeconds = max(0, Int(now.timeIntervalSince(date)))
        if elapsedSeconds < 60 { return "Был(а) менее минуты назад" }
        let minutes = elapsedSeconds / 60
        if minutes < 5 { return "Был(а) \(minutes) мин. назад" }

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
