import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/share_profile/share_profile_view.dart`: QR card + share sheet + copy link.
struct ShareProfileView: View {
    @State private var model: ShareProfileViewModel

    init(dependencies: Dependencies, userId: String, user: UserModel?) {
        _model = State(initialValue: ShareProfileViewModel(dependencies: dependencies, userId: userId, user: user))
    }

    var body: some View {
        Group {
            if let user = model.user {
                content(user)
            } else if let message = model.errorMessage {
                ErrorView(message) { Task { await model.load() } }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("share profile")
        .navigationBarTitleDisplayMode(.inline)
        .glassToast($model.toast)
        .task { await model.load() }
    }

    private func content(_ user: UserModel) -> some View {
        ScrollView {
            VStack(spacing: TappedSpacing.xxl) {
                ShareProfileCard(user: user)
                    .padding(.horizontal, TappedSpacing.xxl)

                GlassEffectContainer(spacing: TappedSpacing.sm) {
                    HStack(spacing: TappedSpacing.sm) {
                        ShareLink(item: user.profileURL, subject: Text(user.displayName), message: Text("check out \(user.displayName) on tapped")) {
                            SwiftUI.Label("share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .padding(.horizontal, TappedSpacing.xl)
                                .frame(height: GlassMetrics.control)
                                .foregroundStyle(TappedColors.accent)
                                .glassEffect(.regular.interactive(), in: Capsule())
                                .overlay(Capsule().stroke(TappedColors.accent.opacity(0.6), lineWidth: 1))
                        }
                        GlassCapsuleButton("copy link", systemImage: "link") { model.copyLink() }
                    }
                }
            }
            .padding(.vertical, TappedSpacing.xxl)
        }
        .background(background)
    }

    private var background: some View {
        LinearGradient(colors: [TappedColors.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// The QR "business card" (avatar, name, code, link).
struct ShareProfileCard: View {
    let user: UserModel

    var body: some View {
        VStack(spacing: TappedSpacing.lg) {
            UserAvatar(user: user, size: 72)
            VStack(spacing: 2) {
                Text(user.displayName.lowercased())
                    .font(.title2.weight(.bold))
                Text("@\(user.username.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            QRCodeView(user.profileURL.absoluteString)
                .frame(width: 220, height: 220)
                .padding(TappedSpacing.md)
                .background(.white, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
            Text(user.profileURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(TappedSpacing.xxl)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: TappedRadius.xl * 1.5, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        ShareProfileView(dependencies: .mock(signedIn: true), userId: Samples.performer.id, user: Samples.performer)
    }
}
