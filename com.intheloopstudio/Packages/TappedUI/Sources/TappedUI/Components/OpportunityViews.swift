import SwiftUI
import TappedDomain

/// Opportunity flier image with the accent-gradient placeholder used across gig surfaces.
public struct OpportunityFlier: View {
    let opportunity: Opportunity
    let symbolSize: CGFloat

    public init(opportunity: Opportunity, symbolSize: CGFloat = 34) {
        self.opportunity = opportunity
        self.symbolSize = symbolSize
    }

    public var body: some View {
        Color.clear
            .overlay {
                if let url = opportunity.flierUrl.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            TappedColors.surface
            LinearGradient(
                colors: [TappedColors.accent.opacity(0.55), TappedColors.accent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: Self.symbol(for: opportunity))
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    static func symbol(for opportunity: Opportunity) -> String {
        let genres = Set(opportunity.genres)
        if genres.contains(Genre.jazz.rawValue) { return "music.quarternote.3" }
        if genres.contains(Genre.electronic.rawValue) || genres.contains(Genre.dance.rawValue) { return "headphones" }
        if genres.contains(Genre.folk.rawValue) || genres.contains(Genre.americana.rawValue) { return "guitars" }
        return "music.mic"
    }
}

/// List row for an opportunity (`OpportunitiesResultsView` tile).
public struct OpportunityTile<Trailing: View>: View {
    let opportunity: Opportunity
    let venueName: String?
    let trailing: Trailing

    public init(opportunity: Opportunity, venueName: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.opportunity = opportunity
        self.venueName = venueName
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: TappedSpacing.md) {
            OpportunityFlier(opportunity: opportunity, symbolSize: 18)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: TappedRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.title.lowercased())
                    .font(TappedTypography.headingXs)
                    .lineLimit(1)
                Text(opportunity.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).lowercased())
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
                HStack(spacing: TappedSpacing.xs) {
                    if let venueName {
                        Text(venueName.lowercased()).lineLimit(1)
                        Text("·")
                    }
                    Text(opportunity.isPaid ? "paid" : "unpaid")
                        .foregroundStyle(opportunity.isPaid ? TappedColors.success : .secondary)
                }
                .font(TappedTypography.label)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, TappedSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Round checkmark used by multi-select result lists.
public struct SelectionIndicator: View {
    let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? TappedColors.accent : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(isSelected ? "selected" : "not selected")
    }
}

#Preview("OpportunityFlier") {
    OpportunityFlier(opportunity: Samples.opportunities[1], symbolSize: 56)
        .frame(height: 220)
}

#Preview("OpportunityTile") {
    List {
        OpportunityTile(opportunity: Samples.opportunities[0], venueName: "the camel") {
            Text("applied").font(TappedTypography.label).foregroundStyle(TappedColors.accent)
        }
        OpportunityTile(opportunity: Samples.opportunities[2])
    }
}

#Preview("SelectionIndicator") {
    HStack {
        SelectionIndicator(isSelected: true)
        SelectionIndicator(isSelected: false)
    }
    .padding()
}
