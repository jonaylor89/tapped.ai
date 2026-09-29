import SwiftUI
import TappedDomain
import TappedUI

/// `SheetQuickActions`.
struct SheetQuickActions: View {
    let actions: [QuickAction]
    let push: (Route) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TappedSpacing.sm) {
                ForEach(actions) { action in
                    Button { push(action.route) } label: {
                        VStack(alignment: .leading, spacing: TappedSpacing.md) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(action.isDestructiveTint ? TappedColors.error : TappedColors.accent)
                            Text(action.title)
                                .font(TappedTypography.label.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(minWidth: 80, alignment: .leading)
                        .padding(TappedSpacing.md)
                        .tappedGlass(in: RoundedRectangle(cornerRadius: GlassRadius.control, style: .continuous), interactive: true)
                    }
                    .buttonStyle(GlassPressStyle())
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset)
        }
        .scrollIndicators(.hidden)
    }
}

struct SheetSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(TappedTypography.headingSm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GlassMetrics.edgeInset + TappedSpacing.xs)
            .padding(.top, TappedSpacing.xl)
            .padding(.bottom, TappedSpacing.sm)
    }
}

/// `SheetResultsSection`: first three results + "view all".
struct SheetResultsSection: View {
    let model: DiscoverViewModel
    let push: (Route) -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch model.overlay {
            case .venues:
                ForEach(model.sortedVenueHits.prefix(3)) { venue in
                    VenueRow(venue: venue, isGoodFit: model.isGoodFit(venue)) {
                        push(.profile(userId: venue.id, user: venue))
                    }
                }
                if model.venueHits.count > 3 { viewAll }
            case .gigs:
                ForEach(model.opportunityHits.prefix(3)) { gig in
                    Button { push(.opportunity(opportunityId: gig.id, opportunity: gig)) } label: {
                        OpportunityRow(opportunity: gig)
                    }
                    .buttonStyle(.plain)
                }
                if !model.opportunityHits.isEmpty { viewAll }
            }
            if model.overlay == .venues ? model.venueHits.isEmpty : model.opportunityHits.isEmpty, !model.isSearching {
                GlassEmptyState(
                    model.overlay == .venues ? "no venues here" : "no gigs here",
                    message: "try zooming out or moving the map",
                    systemImage: model.overlay.systemImage
                )
                .padding(.horizontal, GlassMetrics.edgeInset)
            }
        }
    }

    private var viewAll: some View {
        Button("view all") { model.modal = .allResults }
            .font(.body.weight(.bold))
            .foregroundStyle(TappedColors.accent)
            .padding(.vertical, TappedSpacing.sm)
    }
}

struct VenueRow: View {
    let venue: UserModel
    let isGoodFit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            UserTile(user: venue, subtitle: Self.subtitle(venue)) {
                if isGoodFit {
                    Text("for you")
                        .font(.body.weight(.bold))
                        .foregroundStyle(TappedColors.success)
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset + TappedSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    static func subtitle(_ venue: UserModel) -> String {
        guard let info = venue.venueInfo else { return "@\(venue.username.username)" }
        var parts = [info.type.rawValue.lowercased()]
        if let capacity = info.capacity { parts.append("\(capacity) cap") }
        return parts.joined(separator: " · ")
    }
}

struct OpportunityRow: View {
    let opportunity: Opportunity

    var body: some View {
        HStack(spacing: TappedSpacing.md) {
            Image(systemName: "music.mic")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TappedColors.accent)
                .frame(width: 44, height: 44)
                .background(TappedColors.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.title).font(TappedTypography.headingXs).lineLimit(1)
                Text(opportunity.startTime, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if opportunity.isPaid {
                Text("paid").font(TappedTypography.label).foregroundStyle(TappedColors.success)
            }
        }
        .padding(.vertical, TappedSpacing.xs)
        .padding(.horizontal, GlassMetrics.edgeInset + TappedSpacing.xs)
        .contentShape(Rectangle())
    }
}

/// `SheetGenreChips`.
struct SheetGenreChips: View {
    let counts: [(genre: String, count: Int)]

    var body: some View {
        if !counts.isEmpty {
            VStack(spacing: 0) {
                SheetSectionHeader("top genres in area")
                ScrollView(.horizontal) {
                    HStack(spacing: TappedSpacing.sm) {
                        ForEach(counts, id: \.genre) { GlassChip($0.genre, count: $0.count) }
                    }
                    .padding(.horizontal, GlassMetrics.edgeInset)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// `SheetTopPerformers`: blurred + paywall for non-premium users.
struct SheetTopPerformers: View {
    let performers: [UserModel]
    let isPremium: Bool
    let push: (Route) -> Void

    var body: some View {
        if !performers.isEmpty {
            VStack(spacing: 0) {
                SheetSectionHeader("top performers in area")
                ScrollView(.horizontal) {
                    HStack(spacing: TappedSpacing.sm) {
                        ForEach(performers) { performer in
                            Button {
                                push(Route.profile(userId: performer.id, user: performer).requiringPremium(isPremium))
                            } label: {
                                UserCard(user: performer, isLocked: !isPremium)
                            }
                            .buttonStyle(GlassPressStyle())
                        }
                    }
                    .padding(.horizontal, GlassMetrics.edgeInset)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// `SheetFeaturedGigs`.
struct SheetFeaturedGigs: View {
    let opportunities: [Opportunity]
    let push: (Route) -> Void

    var body: some View {
        if !opportunities.isEmpty {
            VStack(spacing: 0) {
                SheetSectionHeader("featured gigs")
                ScrollView(.horizontal) {
                    HStack(spacing: TappedSpacing.md) {
                        ForEach(opportunities) { gig in
                            Button { push(.opportunity(opportunityId: gig.id, opportunity: gig)) } label: {
                                OpportunityCard(opportunity: gig)
                            }
                            .buttonStyle(GlassPressStyle())
                        }
                    }
                    .padding(.horizontal, GlassMetrics.edgeInset)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
