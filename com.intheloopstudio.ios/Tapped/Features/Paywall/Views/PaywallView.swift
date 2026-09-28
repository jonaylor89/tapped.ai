import SwiftUI
import TappedData
import TappedUI

/// `PaywallView`: animated hero, glass feature list, plan picker and a floating purchase CTA.
struct PaywallView: View {
    @State private var model: PaywallViewModel
    @Environment(Router.self) private var router

    init(dependencies: Dependencies) {
        _model = State(initialValue: PaywallViewModel(dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TappedSpacing.xxl) {
                PaywallHero()
                if model.isPremium {
                    GlassEmptyState(
                        "you're already premium",
                        message: "every feature is unlocked. go book that tour.",
                        systemImage: "crown.fill"
                    )
                } else {
                    VStack(spacing: TappedSpacing.md) {
                        ForEach(PaywallViewModel.features, id: \.self) { feature in
                            GlassFeatureRow(feature.title, detail: feature.detail, systemImage: feature.systemImage)
                        }
                    }
                    .padding(.horizontal, GlassMetrics.edgeInset)
                }
            }
            .padding(.bottom, TappedSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle(Route.paywall.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !model.isPremium {
                PaywallPurchaseBar(model: model)
            }
        }
        .overlay {
            if model.phase == .loading && model.products.isEmpty && !model.isPremium {
                LoadingView()
            }
        }
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("okay", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: model.successCount)
        .sensoryFeedback(.error, trigger: model.errorCount)
        .sensoryFeedback(.selection, trigger: model.selectedProductId)
        .animation(GlassMotion.ease, value: model.isPremium)
        .task { await model.load() }
        .task { await model.observeEntitlements() }
    }
}

/// Rive logo animation over an accent gradient + headline (Flutter shows `splash.gif` full-bleed).
private struct PaywallHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.md) {
            RiveView(.loadingLogo)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text("tapped premium")
                .font(TappedTypography.label)
                .textCase(.uppercase)
                .foregroundStyle(TappedColors.accent)
            Text("create a world tour\nfrom your iphone")
                .font(TappedTypography.headingLg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, GlassMetrics.edgeInset)
        .padding(.top, TappedSpacing.lg)
        .background(alignment: .top) {
            LinearGradient(
                colors: [TappedColors.accent.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 320)
            .ignoresSafeArea(edges: .top)
        }
    }
}

/// Floating bottom chrome: plan picker, primary CTA, restore / legal links.
private struct PaywallPurchaseBar: View {
    @Bindable var model: PaywallViewModel

    var body: some View {
        VStack(spacing: TappedSpacing.md) {
            if case let .failed(message) = model.phase {
                ErrorView(message) { Task { await model.load() } }
                    .frame(maxHeight: 160)
            }
            if model.products.count > 1 {
                Picker("plan", selection: $model.selectedProductId) {
                    ForEach(model.products) { product in
                        Text("\(PaywallViewModel.planTitle(product)) · \(product.displayPrice)")
                            .tag(Optional(product.id))
                    }
                }
                .pickerStyle(.segmented)
            }
            Button {
                Task { await model.purchase() }
            } label: {
                ZStack {
                    Text(model.ctaTitle).opacity(model.isPurchasing ? 0 : 1)
                    if model.isPurchasing { ProgressView().tint(.white) }
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
            }
            .buttonStyle(.glassProminent)
            .tint(TappedColors.accent)
            .disabled(model.selectedProduct == nil || model.isBusy)
            .accessibilityHint("starts an app store subscription")

            HStack(spacing: TappedSpacing.lg) {
                Button(model.isRestoring ? "restoring…" : "restore") { Task { await model.restore() } }
                    .disabled(model.isBusy)
                Link("privacy", destination: PaywallViewModel.privacyURL)
                Link("terms", destination: PaywallViewModel.termsURL)
            }
            .font(TappedTypography.bodySm)
            .foregroundStyle(.secondary)
        }
        .padding(TappedSpacing.lg)
        .tappedGlass(.prominent, in: RoundedRectangle(cornerRadius: GlassRadius.sheet, style: .continuous))
        .tappedShadow()
        .padding(.horizontal, TappedSpacing.sm)
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
