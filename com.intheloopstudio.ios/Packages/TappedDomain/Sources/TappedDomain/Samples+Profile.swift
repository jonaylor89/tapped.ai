import Foundation

/// Profile / activity sample data (session 2). Kept separate from `Samples.swift` to avoid merge conflicts.
public extension Samples {
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * hour
    /// Activities sit a few days before `referenceDate` so relative times read as the past.
    private static let activityAnchor = referenceDate.addingTimeInterval(-5 * day)

    /// Extra bookings used by the profile + activity screens (appended to `Samples.bookings` by the mock database).
    static let profileBookings: [Booking] = [
        Booking(
            id: "booking-2",
            requesteeId: performer.id,
            status: .pending,
            startTime: referenceDate.addingTimeInterval(10 * day),
            endTime: referenceDate.addingTimeInterval(10 * day + 3 * hour),
            timestamp: referenceDate.addingTimeInterval(-3 * hour),
            requesterId: "venue-canal",
            name: "late night house residency",
            rate: 40_000,
            genres: [Genre.dance.rawValue, Genre.electronic.rawValue],
            location: venues[3].location
        ),
        Booking(
            id: "booking-3",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-21 * day),
            endTime: referenceDate.addingTimeInterval(-21 * day + 2 * hour),
            timestamp: referenceDate.addingTimeInterval(-40 * day),
            requesterId: "venue-broadberry",
            name: "disco night",
            rate: 30_000,
            genres: [Genre.dance.rawValue, Genre.funk.rawValue],
            location: venues[2].location
        ),
        Booking(
            id: "booking-4",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-60 * day),
            endTime: referenceDate.addingTimeInterval(-60 * day + 2 * hour),
            timestamp: referenceDate.addingTimeInterval(-80 * day),
            requesterId: "venue-balliceaux",
            name: "funk fridays",
            rate: 20_000,
            genres: [Genre.funk.rawValue],
            location: venues[7].location
        ),
    ]

    static let services: [Service] = [
        Service(
            id: "service-nova-set",
            userId: performer.id,
            title: "2 hour dj set",
            description: "house + disco, bring your own sound system or use mine.",
            rate: 30_000,
            rateType: .fixed,
            count: 12
        ),
        Service(
            id: "service-nova-hourly",
            userId: performer.id,
            title: "open format (hourly)",
            description: "weddings, private events and brand activations.",
            rate: 12_500,
            rateType: .hourly,
            count: 4
        ),
        Service(
            id: "service-lowtide-set",
            userId: "performer-lowtide",
            title: "full band set",
            description: "45 minutes of originals.",
            rate: 50_000,
            rateType: .fixed
        ),
    ]

    static let performerReviews: [PerformerReview] = [
        PerformerReview(fields: ReviewFields(
            id: "review-nova-camel",
            bookerId: "venue-camel",
            performerId: performer.id,
            bookingId: "booking-1",
            timestamp: referenceDate.addingTimeInterval(-5 * day),
            overallRating: 5,
            overallReview: "packed the floor all night. easy to work with and showed up early for soundcheck.",
            type: .performer
        )),
        PerformerReview(fields: ReviewFields(
            id: "review-nova-broadberry",
            bookerId: "venue-broadberry",
            performerId: performer.id,
            bookingId: "booking-3",
            timestamp: referenceDate.addingTimeInterval(-20 * day),
            overallRating: 4,
            overallReview: "great set, crowd loved the disco edits.",
            type: .performer
        )),
    ]

    static let bookerReviews: [BookerReview] = [
        BookerReview(fields: ReviewFields(
            id: "review-camel-nova",
            bookerId: "venue-camel",
            performerId: performer.id,
            bookingId: "booking-1",
            timestamp: referenceDate.addingTimeInterval(-4 * day),
            overallRating: 5,
            overallReview: "paid on time and the sound guy was great.",
            type: .booker
        )),
    ]

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
