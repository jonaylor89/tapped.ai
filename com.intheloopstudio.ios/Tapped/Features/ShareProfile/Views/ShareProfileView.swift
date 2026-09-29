import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// Port of `lib/ui/share_profile/share_profile_view.dart`: designed QR card, image + link share, full-screen QR.
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
        .fullScreenCover(isPresented: $model.showsFullScreenQR) {
            if let user = model.user {
                FullScreenQRView(user: user, qrCode: model.qrCode)
            }
        }
    }

    private func content(_ user: UserModel) -> some View {
        ScrollView {
            VStack(spacing: TappedSpacing.xxl) {
                Button { model.showQR() } label: {
                    ShareProfileCard(user: user, avatar: model.avatar, qrCode: model.qrCode)
                        .frame(maxWidth: ShareProfileCardRenderer.cardWidth)
                }
                .buttonStyle(.plain)
                .accessibilityHint("shows the QR code full screen")
                .padding(.horizontal, TappedSpacing.xl)

                GlassEffectContainer(spacing: TappedSpacing.sm) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: TappedSpacing.sm) { actions(user) }
                        VStack(spacing: TappedSpacing.sm) { actions(user) }
                    }
                }
                .padding(.horizontal, TappedSpacing.xl)
            }
            .padding(.vertical, TappedSpacing.xxl)
        }
        .background(background)
    }

    @ViewBuilder
    private func actions(_ user: UserModel) -> some View {
        shareButton(user)
        GlassCapsuleButton("show QR", systemImage: "qrcode") { model.showQR() }
        GlassCapsuleButton("copy link", systemImage: "link") { model.copyLink() }
    }

    @ViewBuilder
    private func shareButton(_ user: UserModel) -> some View {
        let label = SwiftUI.Label("share", systemImage: "square.and.arrow.up")
            .font(.headline)
            .padding(.horizontal, TappedSpacing.xl)
            .frame(minHeight: GlassMetrics.control)
            .foregroundStyle(TappedColors.accent)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay(Capsule().stroke(TappedColors.accent.opacity(0.6), lineWidth: 1))
        let message = Text("check out \(user.displayName) on tapped \(user.profileURL.absoluteString)")
        if let image = model.cardImage {
            ShareLink(
                item: image,
                subject: Text(user.displayName),
                message: message,
                preview: SharePreview(user.displayName, image: image)
            ) { label }
        } else {
            ShareLink(item: user.profileURL, subject: Text(user.displayName), message: message) { label }
        }
    }

    private var background: some View {
        LinearGradient(colors: [TappedColors.accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// The QR "business card": tapped logo, avatar, name as typed, genres, QR of the public profile URL.
/// Drawn without glass so `ImageRenderer` produces the same card that's on screen.
struct ShareProfileCard: View {
    let user: UserModel
    var avatar: UIImage?
    var qrCode: CGImage?

    private var genres: [String] {
        let performer = user.performerInfo?.genres ?? []
        let venue = user.venueInfo?.genres ?? []
        return Array((performer.isEmpty ? venue : performer).prefix(3))
    }

    var body: some View {
        VStack(spacing: TappedSpacing.lg) {
            HStack {
                Image("TappedLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 22)
                    .accessibilityLabel("tapped")
                Spacer()
                Text("scan to book")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: TappedSpacing.md) {
                avatarView
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("@\(user.username.username)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    if !genres.isEmpty {
                        Text(genres.joined(separator: " · "))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            qr
            Text(user.profileURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(TappedSpacing.xl)
        .background(
            LinearGradient(colors: [TappedColors.accent, Color(red: 0.02, green: 0.25, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: TappedRadius.xl * 1.5, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
        } else {
            UserAvatar(user: user, size: 64)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
        }
    }

    private var qr: some View {
        Group {
            if let qrCode {
                Image(decorative: qrCode, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                QRCodeView(user.profileURL.absoluteString)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(TappedSpacing.md)
        .background(.white, in: RoundedRectangle(cornerRadius: TappedRadius.lg, style: .continuous))
        .accessibilityLabel("QR code for \(user.profileURL.absoluteString)")
    }
}

/// Full-screen code for in-person scanning: white background, screen at full brightness, no auto-lock.
struct FullScreenQRView: View {
    let user: UserModel
    let qrCode: CGImage?
    @Environment(\.dismiss) private var dismiss
    @State private var brightness = ScreenBrightness()

    var body: some View {
        VStack(spacing: TappedSpacing.xl) {
            Spacer()
            Text(user.displayName)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text("@\(user.username.username)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Group {
                if let qrCode {
                    Image(decorative: qrCode, scale: 1).resizable().interpolation(.none)
                } else {
                    QRCodeView(user.profileURL.absoluteString)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)
            .padding(.horizontal, TappedSpacing.xxl)
            .accessibilityLabel("QR code for \(user.profileURL.absoluteString)")
            Text("scan to open my tapped profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .persistentSystemOverlays(.hidden)
        .onAppear { brightness.maximize() }
        .onDisappear { brightness.restore() }
    }
}

@MainActor
struct ScreenBrightness {
    private var previous: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    mutating func maximize() {
        guard let screen else { return }
        previous = screen.brightness
        screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    mutating func restore() {
        if let previous { screen?.brightness = previous }
        previous = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

#Preview {
    NavigationStack {
        ShareProfileView(dependencies: .mock(signedIn: true), userId: Samples.performer.id, user: Samples.performer)
    }
}
