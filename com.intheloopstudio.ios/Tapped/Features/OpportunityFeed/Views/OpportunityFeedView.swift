import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `opportunity_feed_view.dart`: a swipeable card deck. Swipe right to apply, left for not interested.
struct OpportunityFeedView: View {
    static let swipeThreshold: CGFloat = 120

    @State private var model: OpportunityFeedViewModel
    @State private var offset: CGSize = .zero
    @State private var isAnimatingOut = false
    @Environment(Router.self) private var router

    init(dependencies: Dependencies, currentUser: UserModel, isPremium: Bool) {
        _model = State(initialValue: OpportunityFeedViewModel(dependencies: dependencies, currentUser: currentUser, isPremium: isPremium))
    }

    var body: some View {
        Group {
            if model.isLoading && model.opportunities.isEmpty {
                LoadingView()
            } else if model.failed {
                ErrorView("couldn't load your feed") { Task { await model.load() } }
            } else if model.isCaughtUp {
                caughtUp
            } else {
                deck
            }
        }
        .background(TappedColors.background)
        .navigationTitle("gig feed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let quota = model.remainingQuota {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(quota) left")
                        .font(TappedTypography.label)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(quota) free applications left")
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.appliedCount)
        .task { await model.load() }
    }

    private var deck: some View {
        VStack(spacing: TappedSpacing.lg) {
            ZStack {
                if let next = model.next {
                    FeedCard(opportunity: next, venue: model.venue(for: next), stamp: nil)
                        .scaleEffect(0.94)
                        .offset(y: 18)
                        .opacity(0.7)
                        .allowsHitTesting(false)
                }
                if let current = model.current {
                    FeedCard(opportunity: current, venue: model.venue(for: current), stamp: stamp)
                        .id(current.id)
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .gesture(drag)
                        .onTapGesture {
                            router.push(.opportunity(opportunityId: current.id, opportunity: current))
                        }
                        .accessibilityAction(named: "apply") { Task { await swipe(.apply) } }
                        .accessibilityAction(named: "not interested") { Task { await swipe(.dislike) } }
                        .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .identity))
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset)

            controls
        }
        .padding(.vertical, TappedSpacing.md)
    }

    private var stamp: FeedCard.Stamp? {
        if offset.width > 40 { return .apply(progress: min(offset.width / Self.swipeThreshold, 1)) }
        if offset.width < -40 { return .pass(progress: min(-offset.width / Self.swipeThreshold, 1)) }
        return nil
    }

    private var controls: some View {
        GlassEffectContainer(spacing: TappedSpacing.xl) {
            HStack(spacing: TappedSpacing.xl) {
                controlButton("not interested", systemImage: "xmark", tint: TappedColors.error) { await swipe(.dislike) }
                controlButton("skip", systemImage: "arrow.uturn.down", tint: .secondary, size: 48) { await swipe(.dismiss) }
                controlButton("apply", systemImage: "paperplane.fill", tint: TappedColors.success) { await swipe(.apply) }
            }
        }
        .disabled(isAnimatingOut || model.current == nil)
    }

    private func controlButton(_ title: String, systemImage: String, tint: Color, size: CGFloat = 64, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                if value.translation.width > Self.swipeThreshold {
                    Task { await swipe(.apply) }
                } else if value.translation.width < -Self.swipeThreshold {
                    Task { await swipe(.dislike) }
                } else {
                    withAnimation(GlassMotion.spring) { offset = .zero }
                }
            }
    }

    private func swipe(_ action: OpportunityFeedViewModel.SwipeAction) async {
        guard !isAnimatingOut else { return }
        isAnimatingOut = true
        let direction: CGFloat = switch action {
        case .apply: 1
        case .dislike: -1
        case .dismiss: 0
        }
        withAnimation(.easeIn(duration: 0.22)) {
            offset = action == .dismiss ? CGSize(width: 0, height: 900) : CGSize(width: direction * 600, height: offset.height + 40)
        }
        try? await Task.sleep(for: .milliseconds(220))
        let outcome = await model.perform(action)
        offset = .zero
        isAnimatingOut = false
        if outcome == .needsPremium {
            router.push(.paywall)
        }
    }

    private var caughtUp: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: GlassRadius.sheet, style: .continuous)
                .fill(LinearGradient(colors: [TappedColors.accent.opacity(0.7), TappedColors.accent.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 88, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            VStack(spacing: TappedSpacing.sm) {
                Text("you're all caught up")
                    .font(TappedTypography.headingMd)
                Text("you've gone through every gig opportunity in your area. check back soon.")
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(TappedSpacing.xl)
            .frame(maxWidth: .infinity)
            .tappedGlass(.regular, in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
            .padding(GlassMetrics.edgeInset)
        }
        .padding(GlassMetrics.edgeInset)
    }
}

/// Full-bleed flier card with a glass info panel, as in the Flutter feed.
struct FeedCard: View {
    enum Stamp: Equatable {
        case apply(progress: CGFloat)
        case pass(progress: CGFloat)
    }

    let opportunity: Opportunity
    let venue: UserModel?
    let stamp: Stamp?

    var body: some View {
        OpportunityFlier(opportunity: opportunity, symbolSize: 96)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: TappedSpacing.sm) {
                    Text(opportunity.title.lowercased())
                        .font(TappedTypography.headingMd)
                        .lineLimit(2)
                    Text(OpportunityDetailContent.dateLine(opportunity))
                        .font(TappedTypography.bodySm)
                        .foregroundStyle(.secondary)
                    HStack(spacing: TappedSpacing.sm) {
                        if let venue {
                            UserAvatar(user: venue, size: 24)
                            Text(venue.displayName.lowercased())
                                .font(TappedTypography.label)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(opportunity.isPaid ? "paid gig" : "unpaid")
                            .font(TappedTypography.label.weight(.bold))
                            .foregroundStyle(opportunity.isPaid ? TappedColors.success : .secondary)
                    }
                    if !opportunity.description.isEmpty {
                        Text(opportunity.description)
                            .font(TappedTypography.bodySm)
                            .lineLimit(3)
                    }
                }
                .padding(TappedSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tappedGlass(.regular, in: RoundedRectangle(cornerRadius: GlassRadius.card, style: .continuous))
                .padding(TappedSpacing.md)
            }
            .overlay(alignment: .top) { stampView }
            .clipShape(RoundedRectangle(cornerRadius: GlassRadius.sheet, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: GlassRadius.sheet, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityHint("swipe right to apply, left if you're not interested")
    }

    @ViewBuilder
    private var stampView: some View {
        switch stamp {
        case let .apply(progress):
            stampLabel("apply", systemImage: "paperplane.fill", tint: TappedColors.success, progress: progress)
        case let .pass(progress):
            stampLabel("not interested", systemImage: "xmark", tint: TappedColors.error, progress: progress)
        case nil:
            EmptyView()
        }
    }

    private func stampLabel(_ title: String, systemImage: String, tint: Color, progress: CGFloat) -> some View {
        SwiftUI.Label(title, systemImage: systemImage)
            .font(TappedTypography.headingSm)
            .foregroundStyle(tint)
            .padding(.horizontal, TappedSpacing.lg)
            .padding(.vertical, TappedSpacing.sm)
            .tappedGlass(.regular, in: Capsule())
            .opacity(progress)
            .padding(.top, TappedSpacing.xl)
    }
}

#Preview("feed") {
    NavigationStack {
        OpportunityFeedView(dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: false)
    }
    .environment(Router())
}

#Preview("card") {
    FeedCard(opportunity: Samples.opportunities[1], venue: Samples.venues[3], stamp: .apply(progress: 1))
        .frame(height: 560)
        .padding()
}
