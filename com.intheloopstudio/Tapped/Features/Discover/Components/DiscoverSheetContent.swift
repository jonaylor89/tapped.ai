import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Root of the Gigs tab inside the map sheet. For performers the collapsed header leads with whatever the map shows
/// (venues by default, or gigs) and links to the other; `.medium` adds paid gigs this week → venues that fit →
/// finish setting up, then the wider results.
struct DiscoverSheetContent: View {
    @Bindable var model: DiscoverViewModel
    let pendingRequests: Int
    let openBookings: () -> Void
    let expand: () -> Void
    /// Header height (it starts at the sheet's top edge), used to size the collapsed detent.
    let onHeaderHeight: (CGFloat) -> Void
    @Environment(Router.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The collapsed detent only has room for the header; the list fades in as the sheet rises.
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    private var bodyOpacity: CGFloat { min(max(model.sheetProgress / 0.1, 0), 1) }

    var body: some View {
        List {
            if model.isPerformerFirst, isAccessibilitySize {
                Section { secondaryLine }
            }
            if let quota = model.quotaMessage {
                Section {
                    Button { router.push(.paywall) } label: {
                        Label(quota, systemImage: "bolt.fill")
                            .font(TappedTypography.bodySm.weight(.semibold))
                            .foregroundStyle(TappedColors.warning)
                    }
                }
                .listRowBackground(TappedColors.background)
            }
            if model.isPerformerFirst {
                paidGigsThisWeek
                venuesThatFit
            }
            if model.incompleteTaskCount > 0 {
                Section {
                    SetupChecklistRow(progress: model.setupProgress, remaining: model.incompleteTaskCount) { router.push(.tasks) }
                }
                .listRowBackground(TappedColors.background)
            }
            if !model.quickActions.isEmpty {
                plainSection { SheetQuickActions(actions: model.quickActions, push: router.push) }
            }
            plainSection {
                SheetSectionHeader(model.overlay == .venues ? "venues nearby" : "gigs nearby")
                SheetResultsSection(model: model, push: router.push)
            }
            if model.overlay == .venues {
                plainSection { SheetGenreChips(counts: model.genreCounts) }
            }
            plainSection { SheetTopPerformers(performers: model.featuredPerformers, isPremium: model.isPremium, push: router.push) }
            plainSection { SheetFeaturedGigs(opportunities: model.featuredOpportunities, push: router.push) }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(TappedSpacing.md)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .opacity(bodyOpacity)
        .allowsHitTesting(bodyOpacity > 0.5)
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .background {
                    // Ideal height, not the laid-out one, so a short sheet can't shrink its own measurement.
                    header
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeaderHeight($0) }
                }
                .background(TappedColors.surface)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
            if pendingRequests > 0 {
                Button(action: openBookings) {
                    Label("\(pendingRequests) \(pendingRequests == 1 ? "request" : "requests") waiting ›", systemImage: "tray.full.fill")
                        .font(TappedTypography.label.weight(.semibold))
                        .foregroundStyle(TappedColors.accent)
                }
                .buttonStyle(.plain)
                .padding(.bottom, TappedSpacing.xs)
            }
            HStack(alignment: .firstTextBaseline) {
                if model.isPerformerFirst {
                    Button(action: leadsWithGigs ? openGigs : expand) {
                        Text(leadsWithGigs ? gigsLine : venuesLine).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(model.headerTitle)
                        .font(TappedTypography.headingMd)
                        .contentTransition(.numericText())
                }
                if model.isSearching { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                if let filterLabel = model.genreFilterLabel {
                    Label(filterLabel, systemImage: "slider.horizontal.3")
                        .font(TappedTypography.label)
                        .foregroundStyle(TappedColors.accent)
                }
            }
            if model.isPerformerFirst, !isAccessibilitySize { secondaryLine }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlassMetrics.edgeInset + TappedSpacing.xs)
        .padding(.top, TappedSpacing.xl)
        .padding(.bottom, TappedSpacing.md)
    }

    private var leadsWithGigs: Bool { model.overlay == .gigs }

    private func openGigs() {
        if model.opportunityHits.isEmpty { expand() } else { router.push(.opportunities(model.opportunityHits)) }
    }

    private var weekendSuffix: String {
        let weekend = isAccessibilitySize ? 0 : model.gigsThisWeekendCount
        return weekend > 0 ? " · \(weekend) this weekend ›" : " ›"
    }

    /// "**4 open gigs near you** · 2 this weekend ›"
    private var gigsLine: AttributedString { headline(model.gigsHeadline, rest: weekendSuffix) }

    /// "**10 venues booking indie pop** ›"
    private var venuesLine: AttributedString { headline(model.venuesHeadline, rest: " ›") }

    private func headline(_ title: String, rest: String) -> AttributedString {
        var line = AttributedString(title)
        line.font = TappedTypography.headingSm.bold()
        var tail = AttributedString(rest)
        tail.font = TappedTypography.bodySm
        tail.foregroundColor = .secondary
        return line + tail
    }

    /// The other overlay's count under the headline: venues under gigs, gigs under venues.
    private var secondaryLine: some View {
        Button(action: leadsWithGigs ? expand : openGigs) {
            Text(leadsWithGigs ? "\(model.venuesHeadline) ›" : model.gigsHeadline + weekendSuffix)
                .font(TappedTypography.bodySm)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: Medium sections

    @ViewBuilder private var paidGigsThisWeek: some View {
        let gigs = model.paidGigsThisWeek
        if !gigs.isEmpty {
            Section {
                ForEach(gigs) { gig in
                    Button { router.push(.opportunity(opportunityId: gig.id, opportunity: gig)) } label: {
                        PaidGigRow(opportunity: gig, venueName: model.venueName(for: gig))
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionTitle("paid gigs this week")
            }
            .listRowBackground(TappedColors.background)
        }
    }

    @ViewBuilder private var venuesThatFit: some View {
        let venues = model.goodFitVenues
        if !venues.isEmpty {
            Section {
                ForEach(venues.prefix(5)) { venue in
                    Button { router.push(.profile(userId: venue.id, user: venue)) } label: {
                        UserTile(user: venue, subtitle: VenueRow.subtitle(venue))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { router.push(.requestToPerform(venues: [venue], collaborators: [])) } label: {
                            Label("pitch", systemImage: "paperplane")
                        }
                        .tint(TappedColors.accent)
                    }
                    .accessibilityAction(named: "pitch") { router.push(.requestToPerform(venues: [venue], collaborators: [])) }
                }
            } header: {
                sectionTitle("venues that fit you")
            }
            .listRowBackground(TappedColors.background)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(TappedTypography.headingSm)
            .foregroundStyle(.primary)
            .textCase(nil)
    }

    private func plainSection(@ViewBuilder _ content: () -> some View) -> some View {
        Section {
            VStack(spacing: 0) { content() }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

/// Date + venue + green **paid** label.
struct PaidGigRow: View {
    let opportunity: Opportunity
    let venueName: String?

    var body: some View {
        HStack(spacing: TappedSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.title).font(TappedTypography.headingXs)
                HStack(spacing: 0) {
                    Text(opportunity.startTime, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    if let venueName { Text(" · \(venueName)") }
                }
                .font(TappedTypography.bodySm)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: TappedSpacing.sm)
            Text("paid")
                .font(TappedTypography.label.weight(.bold))
                .foregroundStyle(TappedColors.success)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// "finish setting up" with a progress ring (the map banner's in-sheet form).
struct SetupChecklistRow: View {
    let progress: Double
    let remaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TappedSpacing.md) {
                ZStack {
                    Circle().stroke(TappedColors.accent.opacity(0.2), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(TappedColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("finish setting up").font(TappedTypography.headingXs)
                    Text("\(remaining) \(remaining == 1 ? "task" : "tasks") left to get booked")
                        .font(TappedTypography.bodySm)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent complete")
    }
}
