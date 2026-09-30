import Foundation
import Observation
import TappedData
import TappedDomain

/// Port of `user_reviews_feed.dart`: performer + booker reviews for a user, newest first, with reviewer lookup.
@Observable
@MainActor
final class UserReviewsViewModel {
    static let pageSize = 20

    let userId: String
    let currentUser: UserModel
    private(set) var reviewee: UserModel?
    private(set) var reviews: [Review] = []
    private(set) var reviewers: [String: UserModel] = [:]
    private(set) var isLoading = true
    private(set) var failed = false
    private var bookingId: String?

    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies, currentUser: UserModel, userId: String) {
        self.userId = userId
        self.currentUser = currentUser
        database = dependencies.database
        analytics = dependencies.analytics
    }

    var averageRating: Double? {
        guard !reviews.isEmpty else { return nil }
        return Double(reviews.map(\.fields.overallRating).reduce(0, +)) / Double(reviews.count)
    }

    var canWriteReview: Bool {
        !isLoading && currentUser.id != userId && !reviews.contains { Self.reviewerId(of: $0) == currentUser.id }
    }

    /// Venues are reviewed as bookers; everyone else as performers.
    var reviewType: ReviewType { reviewee?.isVenue == true ? .booker : .performer }

    static func reviewerId(of review: Review) -> String {
        switch review {
        case let .performer(review): review.fields.bookerId
        case let .booker(review): review.fields.performerId
        }
    }

    func reviewer(for review: Review) -> UserModel? {
        reviewers[Self.reviewerId(of: review)]
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let user = database.getUserById(userId)
        async let performerReviews = database.getPerformerReviewsByPerformerId(userId, limit: Self.pageSize, lastReviewId: nil)
        async let bookerReviews = database.getBookerReviewsByBookerId(userId, limit: Self.pageSize, lastReviewId: nil)
        do {
            let merged = try await performerReviews.map(Review.performer) + bookerReviews.map(Review.booker)
            reviews = merged.sorted { $0.fields.timestamp > $1.fields.timestamp }
            failed = false
        } catch {
            failed = true
        }
        reviewee = (try? await user) ?? nil
        await loadReviewers()
        bookingId = await sharedBookingId()
    }

    func submit(rating: Int, text: String) async -> Bool {
        let fields = ReviewFields(
            id: UUID().uuidString,
            bookerId: reviewType == .booker ? userId : currentUser.id,
            performerId: reviewType == .booker ? currentUser.id : userId,
            bookingId: bookingId,
            timestamp: .now,
            overallRating: rating,
            overallReview: text.trimmingCharacters(in: .whitespacesAndNewlines),
            type: reviewType
        )
        do {
            let review: Review
            switch reviewType {
            case .booker:
                let booker = BookerReview(fields: fields)
                try await database.createBookerReview(booker)
                review = .booker(booker)
            case .performer:
                let performer = PerformerReview(fields: fields)
                try await database.createPerformerReview(performer)
                review = .performer(performer)
            }
            reviews.insert(review, at: 0)
            reviewers[currentUser.id] = currentUser
            await analytics.track("review_created", properties: ["reviewee_id": .string(userId), "rating": .int(rating)])
            return true
        } catch {
            return false
        }
    }

    private func loadReviewers() async {
        for id in Set(reviews.map(Self.reviewerId(of:))) where reviewers[id] == nil {
            if let user = try? await database.getUserById(id) {
                reviewers[id] = user
            }
        }
    }

    /// Link the review to the most recent confirmed booking between the two users, if any.
    private func sharedBookingId() async -> String? {
        guard currentUser.id != userId else { return nil }
        async let asRequester = database.getBookingsByRequesterRequestee(currentUser.id, userId, limit: 1, lastBookingRequestId: nil, status: .confirmed)
        async let asRequestee = database.getBookingsByRequesterRequestee(userId, currentUser.id, limit: 1, lastBookingRequestId: nil, status: .confirmed)
        let bookings = ((try? await asRequester) ?? []) + ((try? await asRequestee) ?? [])
        return bookings.max { $0.startTime < $1.startTime }?.id
    }
}
