import Foundation

public extension Samples {
    /// Reviews of performers, written by venues.
    static let performerReviews: [PerformerReview] = [
        performerReview("review-camel-nova", booker: "venue-camel", performer: performer.id, booking: "booking-1", daysAgo: 3, rating: 5, text: "packed the room on a tuesday. crowd didn't want to leave. book nova."),
        performerReview("review-canal-nova", booker: "venue-canal", performer: performer.id, daysAgo: 18, rating: 5, text: "flawless four-hour set, great communication before the show."),
        performerReview("review-vagabond-nova", booker: "venue-vagabond", performer: performer.id, daysAgo: 41, rating: 4, text: "good energy and on time. would love a slightly mellower opener next time."),
        performerReview("review-balliceaux-mara", booker: "venue-balliceaux", performer: "performer-mara", daysAgo: 9, rating: 5, text: "mara's trio sold out both nights."),
    ]

    /// Reviews of bookers, written by performers.
    static let bookerReviews: [BookerReview] = [
        bookerReview("review-nova-camel", booker: "venue-camel", performer: performer.id, booking: "booking-1", daysAgo: 2, rating: 5, text: "the camel's sound crew is the best in the city. paid same night."),
        bookerReview("review-lowtide-camel", booker: "venue-camel", performer: "performer-lowtide", daysAgo: 25, rating: 4, text: "great room, load-in is a little tight."),
    ]

    /// `opportunities/{id}/interestedUsers` seed: opportunity id → applicant user ids.
    static let applicants: [String: [String]] = [
        "op-friday-openers": ["performer-lowtide", "performer-kilo"],
        "op-jazz-brunch": ["performer-mara"],
    ]

    private static func performerReview(_ id: String, booker: String, performer: String, booking: String? = nil, daysAgo: Double, rating: Int, text: String) -> PerformerReview {
        PerformerReview(fields: ReviewFields(
            id: id, bookerId: booker, performerId: performer, bookingId: booking,
            timestamp: referenceDate.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            overallRating: rating, overallReview: text, type: .performer
        ))
    }

    private static func bookerReview(_ id: String, booker: String, performer: String, booking: String? = nil, daysAgo: Double, rating: Int, text: String) -> BookerReview {
        BookerReview(fields: ReviewFields(
            id: id, bookerId: booker, performerId: performer, bookingId: booking,
            timestamp: referenceDate.addingTimeInterval(-daysAgo * 24 * 60 * 60),
            overallRating: rating, overallReview: text, type: .booker
        ))
    }
}
