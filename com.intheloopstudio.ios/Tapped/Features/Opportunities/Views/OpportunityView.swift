import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `opportunity_view.dart`: flier hero, facts, venue/booker, floating apply bar.
struct OpportunityView: View {
    @State private var model: OpportunityViewModel
    @State private var showsApplySheet: Bool
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    init(
        dependencies: Dependencies, currentUser: UserModel, isPremium: Bool, claims: [CustomClaim],
        opportunityId: String, opportunity: Opportunity?, showsApplySheet: Bool = false
    ) {
        _model = State(initialValue: OpportunityViewModel(
            dependencies: dependencies, currentUser: currentUser, isPremium: isPremium, claims: claims,
            opportunityId: opportunityId, opportunity: opportunity
        ))
        _showsApplySheet = State(initialValue: showsApplySheet)
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView()
            case .notFound:
                GlassEmptyState("opportunity not found", message: "it may have been removed", systemImage: "questionmark.folder")
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
                    ShareLink(item: url) { SwiftUI.Label("share opportunity", systemImage: "square.and.arrow.up") }
                }
            }
            if model.canSeeApplicants, let opportunity = model.opportunity {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("see applicants", systemImage: "person.2") { router.push(.interestedUsers(opportunity)) }
                }
            }
        }
        .alert("something went wrong", isPresented: Binding { model.errorMessage != nil } set: { if !$0 { model.dismissError() } }) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task { await model.load() }
    }

    private func content(_ opportunity: Opportunity) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OpportunityFlier(opportunity: opportunity, symbolSize: 72)
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
        GlassEffectContainer(spacing: TappedSpacing.md) {
            HStack(spacing: TappedSpacing.md) {
                if !model.isApplied {
                    Button {
                        Task {
                            await model.dislike()
                            if model.isDisliked { dismiss() }
                        }
                    } label: {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("not interested")
                }
                Button {
                    showsApplySheet = true
                } label: {
                    SwiftUI.Label(model.isApplied ? "applied" : (model.isPastDeadline ? "deadline passed" : "apply"),
                                  systemImage: model.isApplied ? "checkmark" : "paperplane.fill")
                        .font(TappedTypography.headingXs)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.isApplied || model.isPastDeadline)
            }
        }
        .tappedFloatingInset()
        .padding(.bottom, TappedSpacing.sm)
        .animation(GlassMotion.spring, value: model.isApplied)
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
