import SwiftUI

/// Five-star rating (reviews, profile info). Supports half stars for averages.
public struct RatingStars: View {
    let rating: Double
    let size: CGFloat
    @ScaledMetric(relativeTo: .footnote) private var scale: CGFloat = 1

    public init(_ rating: Double, size: CGFloat = 14) {
        self.rating = rating
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: size * scale, height: size * scale)
                    .foregroundStyle(TappedColors.accent)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", rating))
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

#Preview("RatingStars") {
    VStack(spacing: TappedSpacing.md) {
        RatingStars(5)
        RatingStars(4.5, size: 20)
        RatingStars(2)
    }
    .padding()
}
