import Foundation

/// Profile / activity sample data (session 2). Kept separate from `Samples.swift` to avoid merge conflicts.
public extension Samples {
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * hour
    /// Activities sit a few days before `referenceDate` so relative times read as the past.
    private static let activityAnchor = referenceDate.addingTimeInterval(-5 * day)

    /// Activities for `Samples.performer`, newest first. Enough rows to exercise pagination (page size 20).
    static let activities: [Activity] = {
        let to = performer.id
        func common(_ id: String, _ offset: TimeInterval, read: Bool) -> Activity.Common {
            Activity.Common(id: id, toUserId: to, timestamp: activityAnchor.addingTimeInterval(-offset), markedRead: read)
        }
        var items: [Activity] = [
            .bookingRequest(.init(common: common("activity-request", 3 * hour, read: false), fromUserId: "venue-canal", bookingId: "booking-2")),
            .follow(.init(common: common("activity-follow-lowtide", 5 * hour, read: false), fromUserId: "performer-lowtide")),
            .searchAppearance(.init(common: common("activity-search", 1 * day, read: false), count: 14)),
            .bookingReminder(.init(common: common("activity-reminder", 2 * day, read: true), fromUserId: "venue-camel", bookingId: "booking-1")),
            .bookingUpdate(.init(common: common("activity-update", 3 * day, read: true), fromUserId: "venue-camel", bookingId: "booking-1", status: .confirmed)),
            .follow(.init(common: common("activity-follow-mara", 4 * day, read: true), fromUserId: "performer-mara")),
        ]
        let followers = venues + performers.filter { $0.id != to }
        for index in 0..<20 {
            let from = followers[index % followers.count]
            items.append(.follow(.init(common: common("activity-follow-\(index)", Double(5 + index) * day, read: true), fromUserId: from.id)))
        }
        return items
    }()
}
