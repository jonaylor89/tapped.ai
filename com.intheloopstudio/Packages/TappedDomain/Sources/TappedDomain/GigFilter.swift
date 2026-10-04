import Foundation

/// "Paid gigs this weekend"-style narrowing of opportunities (App Shortcuts, `com.intheloopstudio://gigs?paid=1&when=weekend`).
public struct GigFilter: Hashable, Sendable {
    public var paidOnly: Bool
    public var weekendOnly: Bool

    public init(paidOnly: Bool = false, weekendOnly: Bool = false) {
        self.paidOnly = paidOnly
        self.weekendOnly = weekendOnly
    }

    public static let paidThisWeekend = GigFilter(paidOnly: true, weekendOnly: true)

    /// Friday 5 pm through Sunday night: the weekend in progress, or the next one.
    public static func weekend(around now: Date, calendar: Calendar = .current) -> DateInterval? {
        let weekend = calendar.isDateInWeekend(now)
            ? calendar.dateIntervalOfWeekend(containing: now)
            : calendar.nextWeekend(startingAfter: now)
        guard let weekend, let fridayNight = calendar.date(byAdding: .hour, value: -7, to: weekend.start) else { return nil }
        return DateInterval(start: fridayNight, end: weekend.end)
    }

    public func matches(_ opportunity: Opportunity, now: Date, calendar: Calendar = .current) -> Bool {
        guard !opportunity.deleted, opportunity.endTime > now else { return false }
        if paidOnly, !opportunity.isPaid { return false }
        if weekendOnly {
            guard let weekend = Self.weekend(around: now, calendar: calendar) else { return false }
            return opportunity.startTime < weekend.end && opportunity.endTime > weekend.start
        }
        return true
    }

    public func apply(_ opportunities: [Opportunity], now: Date, calendar: Calendar = .current) -> [Opportunity] {
        opportunities.filter { matches($0, now: now, calendar: calendar) }.sorted { $0.startTime < $1.startTime }
    }
}
