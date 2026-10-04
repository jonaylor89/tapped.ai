import SwiftUI
import TappedDomain
import TappedUI

/// Full-bleed profile photo with a scrim and the name/username overlay (`header_sliver.dart`).
struct ProfileHero: View {
    let user: UserModel
    let subtitle: String?
    var onTapImage: ((URL) -> Void)?

    nonisolated static let height: CGFloat = 440
    /// Photo-less profiles get a short gradient band instead of a giant-initials hero.
    nonisolated static let compactHeight: CGFloat = 320
    /// How far `ProfileStats` is pulled up over the bottom of the hero.
    static let statsOverlap: CGFloat = TappedSpacing.xxxl + TappedSpacing.lg

    private var imageURL: URL? { user.profilePicture.flatMap(URL.init(string:)) }
    private var height: CGFloat { imageURL == nil ? Self.compactHeight : Self.height }

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.xs) {
            Spacer(minLength: 0)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, TappedSpacing.sm)
                        .padding(.vertical, TappedSpacing.xs)
                        .glassEffect(.regular, in: Capsule())
                }
                Text(user.displayName)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text("@\(user.username.username)")
                    .font(.headline)
                    .opacity(0.85)
            }
        .foregroundStyle(.white)
        .padding(.horizontal, TappedSpacing.lg)
        .padding(.bottom, Self.statsOverlap + TappedSpacing.lg)
        .padding(.top, 120)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            ZStack {
                artwork
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture { if let imageURL { onTapImage?(imageURL) } }
                    .accessibilityAddTraits(imageURL == nil ? [] : .isButton)
                    .accessibilityLabel("profile photo")
                LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .stretchyHeader()
    }

    private var artwork: some View {
        RemoteImage(url: imageURL) { placeholder }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [TappedColors.accent.opacity(0.9), TappedColors.accent.opacity(0.35), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private extension View {
    /// Pins the top edge and grows the view when the scroll view is over-pulled.
    func stretchyHeader() -> some View {
        visualEffect { content, proxy in
            let overscroll = max(0, proxy.frame(in: .scrollView).minY)
            return content
                .scaleEffect(1 + overscroll / ProfileHero.height, anchor: .bottom)
                .offset(y: -overscroll / 2)
        }
    }
}

#Preview {
    ScrollView {
        ProfileHero(user: Samples.performer, subtitle: "hometown hero")
    }
    .ignoresSafeArea()
}
