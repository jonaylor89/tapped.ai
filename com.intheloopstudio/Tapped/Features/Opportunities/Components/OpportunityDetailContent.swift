import SwiftUI
import TappedDomain
import TappedUI

/// Glass fact capsule ("paid gig", "fri, oct 9 · 9 pm", genres).
struct FactPill: View {
    let text: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        SwiftUI.Label(text, systemImage: systemImage)
            .font(TappedTypography.label)
            .foregroundStyle(tint)
            .padding(.horizontal, TappedSpacing.md)
            .padding(.vertical, TappedSpacing.sm)
            .tappedGlass(.regular, in: Capsule())
    }
}

/// Body of `opportunity_view.dart`, shared by the detail screen and the feed card.
struct OpportunityDetailContent: View {
    let opportunity: Opportunity
    let venue: UserModel?
    let booker: UserModel?
    var onSelectUser: (UserModel) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.lg) {
            VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                Text(opportunity.title.lowercased())
                    .font(TappedTypography.headingLg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.dateLine(opportunity))
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: TappedSpacing.sm) {
                        FactPill(
                            text: opportunity.isPaid ? "paid gig" : "unpaid",
                            systemImage: opportunity.isPaid ? "dollarsign.circle.fill" : "hand.raised.fill",
                            tint: opportunity.isPaid ? TappedColors.success : .secondary
                        )
                        if let deadline = opportunity.deadline {
                            FactPill(text: "apply by \(deadline.formatted(.dateTime.month(.abbreviated).day()).lowercased())", systemImage: "hourglass")
                        }
                        ForEach(opportunity.genres, id: \.self) { genre in
                            FactPill(text: (Genre(rawValue: genre)?.formattedName ?? genre).lowercased(), systemImage: "music.note")
                        }
                    }
                    .padding(.vertical, TappedSpacing.xs)
                }
            }
            .scrollClipDisabled()

            if !opportunity.description.isEmpty {
                Text(opportunity.description)
                    .font(TappedTypography.bodyLg)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let venue {
                userSection("venue", user: venue, subtitle: VenueRow.subtitle(venue))
            }
            if let booker {
                userSection("booker", user: booker, subtitle: "@\(booker.username.username)")
            }
        }
    }

    private func userSection(_ title: String, user: UserModel, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: TappedSpacing.sm) {
            Text(title)
                .font(TappedTypography.label)
                .foregroundStyle(.secondary)
            Button {
                onSelectUser(user)
            } label: {
                UserTile(user: user, subtitle: subtitle) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(TappedSpacing.md)
                .background(TappedColors.surface, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    static func dateLine(_ opportunity: Opportunity) -> String {
        let day = opportunity.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let start = opportunity.startTime.formatted(.dateTime.hour().minute())
        let end = opportunity.endTime.formatted(.dateTime.hour().minute())
        return "\(day) · \(start) – \(end)".lowercased()
    }
}

#Preview {
    ScrollView {
        OpportunityDetailContent(opportunity: Samples.opportunities[0], venue: Samples.venues[0], booker: nil)
            .padding()
    }
}
