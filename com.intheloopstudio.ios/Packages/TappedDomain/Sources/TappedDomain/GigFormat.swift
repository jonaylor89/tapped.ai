import Foundation

/// Copy for gig times shown in the Live Activity and widget: "Fri · The Camel · 9 pm".
/// Venue names are shown as typed; only the generated day/time words are lowercase.
public struct GigFormat: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = .current) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "9 pm", "9:30 pm".
    public func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(calendar.component(.minute, from: date) == 0 ? "j" : "jmm")
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
    }

    /// "9 pm – 11 pm".
    public func setTime(start: Date, end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "tonight" / "today" / "tomorrow" / "Fri" (locale weekday abbreviation).
    public func day(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 17 ? "tonight" : "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    /// "Fri · The Camel · 9 pm".
    public func nextGig(_ gig: GigNight, now: Date) -> String {
        "\(day(gig.startTime, now: now)) · \(gig.venueName) · \(time(gig.startTime))"
    }

    /// Inline Lock Screen widgets sit next to the date, so a gig today drops the day: "The Camel · 9 pm".
    public func nextGigInline(_ gig: GigNight, now: Date) -> String {
        guard calendar.isDate(gig.startTime, inSameDayAs: now) else { return nextGig(gig, now: now) }
        return "\(gig.venueName) · \(time(gig.startTime))"
    }

    /// "4 new gigs near you".
    public static func nearbyGigs(_ count: Int?) -> String {
        switch count {
        case let count? where count == 1: "1 new gig near you"
        case let count? where count > 1: "\(count) new gigs near you"
        default: "find gigs near you"
        }
    }

    /// Static countdown used where a live timer can't run (accessibility labels, widget snapshots): "2h 14m", "14m", "now".
    public static func countdown(from now: Date, to date: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        guard minutes > 0 else { return "now" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// "how was The Camel?"
    public static func reviewPrompt(_ venueName: String) -> String {
        "how was \(venueName)?"
    }
}
