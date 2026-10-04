import SwiftUI
import TappedDomain

extension View {
    /// Booking detail hooks for Gig Night: start the activity when the booking is confirmed, end it once reviewed,
    /// and open the review with the star tapped in the Live Activity.
    func gigNight(_ model: BookingDetailViewModel, showsReview: Binding<Bool>) -> some View {
        modifier(GigNightBookingHooks(model: model, showsReview: showsReview))
    }
}

private struct GigNightBookingHooks: ViewModifier {
    let model: BookingDetailViewModel
    @Binding var showsReview: Bool

    private var isReviewReady: Bool { model.canReview && model.requester != nil }

    func body(content: Content) -> some View {
        content
            .onChange(of: model.booking.status) { old, new in
                guard old != .confirmed, new == .confirmed else { return }
                Task { await GigNightCoordinator.shared.bookingConfirmed(model.booking) }
            }
            .onChange(of: model.hasReviewed) { _, reviewed in
                guard reviewed else { return }
                Task { await GigNightCoordinator.shared.reviewed(bookingId: model.booking.id) }
            }
            .task(id: isReviewReady) {
                guard isReviewReady, let rating = GigNightCoordinator.shared.takePendingRating(for: model.booking.id) else { return }
                model.reviewRating = rating
                showsReview = true
            }
    }
}
