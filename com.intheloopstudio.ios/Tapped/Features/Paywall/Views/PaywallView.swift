import StoreKit
import SwiftUI
import TappedData
import TappedUI

/// StoreKit `SubscriptionStoreView` with tapped marketing on top. Works pushed or in a `.medium`/`.large` sheet
/// and scales with Dynamic Type (StoreKit lays out the plan picker, price and subscribe button).
struct PaywallView: View {
    @State private var model: PaywallViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies) {
        _model = State(initialValue: PaywallViewModel(dependencies: dependencies))
    }

    var body: some View {
        Group {
            if model.isPremium {
                ScrollView {
                    VStack(spacing: TappedSpacing.xxl) {
                        PaywallHero()
                        GlassEmptyState(
                            "you're already premium",
                            message: "every feature is unlocked. go book that tour.",
                            systemImage: "crown.fill"
                        )
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                store
            }
        }
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle(Route.paywall.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: model.successCount)
        .sensoryFeedback(.error, trigger: model.errorCount)
        .animation(GlassMotion.ease, value: model.isPremium)
        .task { await model.load() }
        .task { await model.observeEntitlements() }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: model.productIds) {
            PaywallMarketing()
        }
        .subscriptionStoreControlStyle(.picker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: PaywallViewModel.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: PaywallViewModel.privacyURL, for: .privacyPolicy)
        .subscriptionStorePolicyForegroundStyle(TappedColors.accentText)
        .tint(TappedColors.accent)
        .containerBackground(TappedColors.background, for: .subscriptionStore)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await model.storeCompleted(purchased: true)
            } else if case .failure = result {
                model.notice = ErrorCopy.action("complete the purchase", hint: "you weren't charged. try again")
                await model.storeCompleted(purchased: false)
            }
        }
        .onChange(of: model.isPremium) { _, isPremium in
            if isPremium, router.path.last == .paywall { router.pop() }
        }
    }
}

/// Marketing content above StoreKit's plan picker.
private struct PaywallMarketing: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xl) {
            PaywallHero()
            VStack(spacing: TappedSpacing.md) {
                ForEach(PaywallViewModel.features, id: \.self) { feature in
                    GlassFeatureRow(feature.title, detail: feature.detail, systemImage: feature.systemImage)
                }
            }
            .padding(.horizontal, GlassMetrics.edgeInset)
        }
        .padding(.bottom, TappedSpacing.lg)
    }
}

/// Rive logo animation over an accent gradient + headline (Flutter shows `splash.gif` full-bleed).
private struct PaywallHero: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.md) {
            if !dynamicTypeSize.isAccessibilitySize {
                RiveView(.loadingLogo)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            Text("tapped premium")
                .font(TappedTypography.label)
                .textCase(.uppercase)
                .foregroundStyle(TappedColors.accentText)
            Text("create a world tour from your iphone")
                .font(TappedTypography.headingLg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.top, TappedSpacing.lg)
        .background(alignment: .top) {
            LinearGradient(colors: [TappedColors.accent.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 280)
                .ignoresSafeArea(edges: .top)
        }
    }
}

#Preview("free") {
    NavigationStack {
        PaywallView(dependencies: .mock(signedIn: true))
    }
    .environment(Router())
}

#Preview("premium") {
    NavigationStack {
        PaywallView(dependencies: .mock(signedIn: true, isPremium: true))
    }
    .environment(Router())
}
