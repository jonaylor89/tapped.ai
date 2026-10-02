import SwiftUI
import TappedDomain

/// Featured gig card (`sheet_featured_gigs.dart` / `opportunity_card.dart`).
public struct OpportunityCard: View {
    let opportunity: Opportunity
    let venueName: String?

    public init(opportunity: Opportunity, venueName: String? = nil) {
        self.opportunity = opportunity
        self.venueName = venueName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            flier
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                Text(opportunity.title.lowercased())
                    .font(TappedTypography.headingXs)
                    .lineLimit(1)
                Text(opportunity.startTime, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
                HStack(spacing: TappedSpacing.xs) {
                    if let venueName {
                        Text(venueName.lowercased()).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(opportunity.isPaid ? "paid" : "unpaid")
                        .foregroundStyle(opportunity.isPaid ? TappedColors.success : .secondary)
                }
                .font(TappedTypography.label)
            }
            .padding(TappedSpacing.md)
        }
        .frame(width: 220)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: TappedRadius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var flier: some View {
        RemoteImage(url: opportunity.flierUrl.flatMap(URL.init(string:))) { placeholder }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [TappedColors.accent.opacity(0.35), TappedColors.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.mic").font(.largeTitle).foregroundStyle(TappedColors.accent)
        }
    }
}

#Preview("OpportunityCard") {
    ScrollView(.horizontal) {
        HStack {
            ForEach(Samples.opportunities) { OpportunityCard(opportunity: $0, venueName: "the camel") }
        }
        .padding()
    }
}
