import SwiftUI
import TappedDomain

/// Read-only star rating (`RatingBarIndicator`).
public struct StarRatingView: View {
    let rating: Double
    let size: CGFloat

    public init(rating: Double, size: CGFloat = 14) {
        self.rating = rating
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: symbol(for: star))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(TappedColors.warning)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating.formatted(.number.precision(.fractionLength(0...1)))) out of 5 stars")
    }

    private func symbol(for star: Int) -> String {
        let value = rating - Double(star - 1)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// Tappable 1–5 star picker for the write-review sheet.
public struct StarRatingPicker: View {
    @Binding var rating: Int
    let size: CGFloat

    public init(rating: Binding<Int>, size: CGFloat = 32) {
        _rating = rating
        self.size = size
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.sm) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    withAnimation(GlassMotion.spring) { rating = star }
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(star <= rating ? TappedColors.warning : Color.secondary)
                        .symbolEffect(.bounce, value: rating == star)
                        .frame(minWidth: TappedSizing.minTapTarget, minHeight: TappedSizing.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
    }
}

/// `review_tile.dart`: reviewer tile, stars, date and review body on a card.
public struct ReviewCard: View {
    let review: Review
    let reviewer: UserModel?

    public init(review: Review, reviewer: UserModel?) {
        self.review = review
        self.reviewer = reviewer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.md) {
            HStack(spacing: TappedSpacing.md) {
                if let reviewer {
                    UserAvatar(user: reviewer, size: 40)
                } else {
                    Circle().fill(.fill.tertiary).frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(reviewer?.displayName.lowercased() ?? "tapped user")
                        .font(TappedTypography.headingXs)
                        .lineLimit(1)
                        .redacted(reason: reviewer == nil ? .placeholder : [])
                    Text(review.fields.timestamp.formatted(.dateTime.month(.abbreviated).day().year()).lowercased())
                        .font(TappedTypography.bodySm)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                StarRatingView(rating: Double(review.fields.overallRating))
            }
            if !review.fields.overallReview.isEmpty {
                Text(review.fields.overallReview)
                    .font(TappedTypography.bodyMd)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(TappedSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TappedColors.surface, in: RoundedRectangle(cornerRadius: TappedRadius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("StarRatingView") {
    VStack(spacing: TappedSpacing.md) {
        StarRatingView(rating: 5)
        StarRatingView(rating: 3.5, size: 20)
        StarRatingView(rating: 0)
    }
    .padding()
}

#Preview("StarRatingPicker") {
    @Previewable @State var rating = 3
    StarRatingPicker(rating: $rating).padding()
}

#Preview("ReviewCard") {
    VStack(spacing: TappedSpacing.md) {
        ReviewCard(review: .performer(Samples.performerReviews[0]), reviewer: Samples.venues[0])
        ReviewCard(review: .booker(Samples.bookerReviews[0]), reviewer: nil)
    }
    .padding()
    .background(TappedColors.background)
}
