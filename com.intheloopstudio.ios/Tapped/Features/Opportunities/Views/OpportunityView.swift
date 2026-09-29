import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `opportunity_view.dart`: flier hero, facts, venue/booker, floating apply bar.
struct OpportunityView: View {
    private let isPremium: Bool
    @State private var model: OpportunityViewModel
    @State private var showsApplySheet: Bool
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    init(
        dependencies: Dependencies, currentUser: UserModel, isPremium: Bool, claims: [CustomClaim],
        opportunityId: String, opportunity: Opportunity?, showsApplySheet: Bool = false
    ) {
        self.isPremium = isPremium
        _model = State(initialValue: OpportunityViewModel(
            dependencies: dependencies, currentUser: currentUser, isPremium: isPremium, claims: claims,
            opportunityId: opportunityId, opportunity: opportunity
        ))
        _showsApplySheet = State(initialValue: showsApplySheet)
    }

    var body: some View {
        screen.onChange(of: isPremium) { _, isPremium in model.isPremium = isPremium }
    }

    @ViewBuilder private var screen: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .notFound:
                GlassEmptyState("gig not found", message: "the venue may have filled or removed it", systemImage: "questionmark.folder")
            case .loaded:
                if let opportunity = model.opportunity {
                    content(opportunity)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = model.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { SwiftUI.Label("share gig", systemImage: "square.and.arrow.up") }
                }
            }
            if model.canApply, !model.isApplied {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("more", systemImage: "ellipsis") {
                        Button("not interested", systemImage: "hand.thumbsdown") {
                            Task {
                                await model.dislike()
                                if model.isDisliked { dismiss() }
                            }
                        }
                    }
                }
            }
            if model.canSeeApplicants, let opportunity = model.opportunity {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("see applicants", systemImage: "person.2") { router.push(.interestedUsers(opportunity)) }
                }
            }
        }
        .alert("Something Went Wrong", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.dismissError() } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
    }

    private func content(_ opportunity: Opportunity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OpportunityHero(opportunity: opportunity, venue: model.venue)
                    .frame(height: 340)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, TappedColors.background], startPoint: .top, endPoint: .bottom)
                            .frame(height: 80)
                    }
                OpportunityDetailContent(opportunity: opportunity, venue: model.venue, booker: model.booker) { user in
                    router.push(.profile(userId: user.id, user: user))
                }
                .padding(.horizontal, GlassMetrics.edgeInset)
                .padding(.bottom, TappedSpacing.xxxl)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(TappedColors.background)
        .offlineBanner(isOffline: NetworkMonitor.shared.isOffline)
        .safeAreaBar(edge: .bottom) {
            if model.canApply, !showsApplySheet {
                applyBar
            }
        }
        .sheet(isPresented: $showsApplySheet) {
            ApplySheet(opportunity: opportunity, remainingQuota: model.remainingQuota) { comment in
                await model.apply(comment: comment)
            } onNeedsPremium: {
                router.push(.paywall)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var applyBar: some View {
        VStack(spacing: TappedSpacing.xs) {
            if let caption = model.quotaCaption, !model.isPastDeadline {
                Text(caption)
                    .font(TappedTypography.bodySm)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TappedSpacing.md)
                    .padding(.vertical, TappedSpacing.xs)
                    .tappedGlass(.regular, in: Capsule())
                    .accessibilityIdentifier("quota-caption")
            }
            Button {
                if model.needsPremiumToApply {
                    router.push(.paywall)
                } else {
                    showsApplySheet = true
                }
            } label: {
                SwiftUI.Label(applyTitle, systemImage: applySymbol)
                    .font(TappedTypography.headingXs)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isApplied || model.isPastDeadline)
        }
        .tappedFloatingInset()
        .padding(.bottom, TappedSpacing.sm)
        .animation(GlassMotion.spring, value: model.isApplied)
    }

    private var applyTitle: String {
        if model.isApplied { return "applied" }
        if model.isPastDeadline { return "deadline passed" }
        return model.needsPremiumToApply ? ApplicationQuota.applyWithPremium : "apply"
    }

    private var applySymbol: String {
        if model.isApplied { return "checkmark" }
        return model.needsPremiumToApply ? "sparkles" : "paperplane.fill"
    }
}

#Preview("gig") {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack {
        OpportunityView(
            dependencies: dependencies, currentUser: Samples.performer, isPremium: false, claims: [],
            opportunityId: Samples.opportunities[0].id, opportunity: Samples.opportunities[0]
        )
    }
    .environment(Router())
}

#Preview("owner") {
    let venue = Samples.venues[0]
    NavigationStack {
        OpportunityView(
            dependencies: .mock(signedIn: true), currentUser: venue, isPremium: false, claims: [],
            opportunityId: Samples.opportunities[0].id, opportunity: nil
        )
    }
    .environment(Router())
}
