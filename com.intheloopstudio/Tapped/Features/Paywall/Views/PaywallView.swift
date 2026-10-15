import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// The final onboarding step. Prices come from StoreKit; only verified entitlement unlocks the shell.
struct PaywallView: View {
    @State private var model: PaywallViewModel
    @State private var account: SettingsViewModel
    @State private var confirmsDelete = false
    @State private var reauthenticates = false
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let user: UserModel

    init(dependencies: Dependencies, user: UserModel) {
        self.user = user
        _model = State(initialValue: PaywallViewModel(dependencies: dependencies))
        _account = State(initialValue: SettingsViewModel(dependencies: dependencies, currentUser: user))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TappedSpacing.xl) {
                OnboardingProgress(step: OnboardingViewModel.stepCount, count: OnboardingViewModel.stepCount)
                hero
                VStack(alignment: .leading, spacing: TappedSpacing.lg) {
                    ForEach(PaywallViewModel.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: TappedSpacing.md) {
                            Image(systemName: feature.systemImage)
                                .font(.title3)
                                .foregroundStyle(TappedColors.accentText)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                                Text(feature.title).font(TappedTypography.label)
                                Text(feature.detail).font(TappedTypography.bodySm).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                plans
                purchaseControls
                accountLinks
            }
            .padding(GlassMetrics.edgeInset)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TappedColors.background.ignoresSafeArea())
        .navigationTitle("step \(OnboardingViewModel.stepCount) of \(OnboardingViewModel.stepCount)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("account", systemImage: "ellipsis") {
                    Button("sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await session?.signOut() }
                    }
                    Button("delete account", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                }
                .disabled(model.isBusy || account.isDeleting)
            }
        }
        .alert("delete your account?", isPresented: $confirmsDelete) {
            Button("delete account", role: .destructive) { reauthenticates = true }
            Button("keep account", role: .cancel) {}
        } message: {
            Text("this permanently deletes your profile. deleting your account does not cancel an App Store subscription.")
        }
        .reauthenticationSheet(isPresented: $reauthenticates, reason: "delete your account") {
            Task { _ = await account.deleteAccount() }
        }
        .alert("something went wrong", isPresented: Binding(get: { account.errorMessage != nil }, set: { if !$0 { account.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: { Text(account.errorMessage ?? "") }
        .alert(model.notice ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("ok", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: model.successCount)
        .sensoryFeedback(.error, trigger: model.errorCount)
        .task { await model.load() }
        .task { await model.observeEntitlements() }
        .onChange(of: model.isPremium, initial: true) { _, premium in
            if premium { Task { await session?.refreshPremiumAccess() } }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.md) {
            Text("your profile is ready")
                .font(TappedTypography.label)
                .foregroundStyle(TappedColors.accentText)
            Text("your next stage\nstarts here.")
                .font(TappedTypography.headingLg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("choose tapped premium to start finding gigs, connecting with venues, and building your next tour.")
                .font(TappedTypography.bodySm)
                .foregroundStyle(.secondary)
            Text("one subscription. everything included.")
                .font(TappedTypography.label)
        }
    }

    @ViewBuilder private var plans: some View {
        switch model.phase {
        case .loading:
            ProgressView("loading plans…").frame(maxWidth: .infinity)
        case let .failed(message):
            ErrorView(message) { Task { await model.load() } }
        case .ready:
            VStack(spacing: TappedSpacing.sm) {
                ForEach(model.products) { product in
                    Button {
                        model.selectedProductId = product.id
                    } label: {
                        let layout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: TappedSpacing.sm))
                            : AnyLayout(HStackLayout(spacing: TappedSpacing.md))
                        layout {
                            Image(systemName: model.selectedProduct?.id == product.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(TappedColors.accentText)
                                .accessibilityHidden(true)
                            Text(PaywallViewModel.planTitle(product)).font(TappedTypography.label)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Text(price(product)).font(TappedTypography.label)
                        }
                        .foregroundStyle(.primary)
                        .padding(TappedSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: TappedRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: TappedRadius.md)
                                .strokeBorder(model.selectedProduct?.id == product.id ? TappedColors.accent : .clear, lineWidth: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.selectedProduct?.id == product.id ? [.isSelected] : [])
                    .disabled(model.isBusy)
                }
            }
        }
    }

    private var purchaseControls: some View {
        VStack(spacing: TappedSpacing.md) {
            if let product = model.selectedProduct {
                Text("\(price(product)), billed \(PaywallViewModel.planTitle(product)). auto-renews until cancelled. cancel anytime in App Store settings.")
                    .font(TappedTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await model.purchase() }
            } label: {
                Group {
                    if model.isPurchasing { ProgressView() } else { Text(model.ctaTitle) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(model.selectedProduct == nil || model.isBusy || model.phase != .ready)
            .accessibilityIdentifier("activate-premium")
            Text("a subscription is required to use tapped. your profile is saved if you decide to come back later.")
                .font(TappedTypography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.restore() }
            } label: {
                if model.isRestoring { ProgressView() } else { Text("already subscribed? restore purchases") }
            }
            .disabled(model.isBusy)
            .font(TappedTypography.label)
        }
    }

    private var accountLinks: some View {
        VStack(spacing: TappedSpacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TappedSpacing.lg) { legalLinks }
                VStack(spacing: TappedSpacing.md) { legalLinks }
            }
            Text("by subscribing, you agree to the terms of service and privacy policy.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("manage App Store subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            Link("need help? contact support", destination: URL(string: "mailto:support@tapped.ai")!)
        }
        .font(TappedTypography.caption)
        .tint(TappedColors.accentText)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var legalLinks: some View {
        Link("terms of service", destination: PaywallViewModel.termsURL)
        Link("privacy policy", destination: PaywallViewModel.privacyURL)
    }

    private func price(_ product: PremiumProduct) -> String {
        guard let period = product.period else { return product.displayPrice }
        return "\(product.displayPrice) / \(period.rawValue)"
    }
}

#Preview("activation") {
    NavigationStack {
        PaywallView(dependencies: .mock(signedIn: true), user: Samples.performer)
    }
}
