import SwiftUI
import TappedDomain
import TappedUI

/// Full-bleed profile photo with a scrim and the name/username overlay (`header_sliver.dart`).
struct ProfileHero: View {
    let user: UserModel
    let subtitle: String?
    var onTapImage: ((URL) -> Void)?

    nonisolated static let height: CGFloat = 440
    /// How far `ProfileStats` is pulled up over the bottom of the hero.
    static let statsOverlap: CGFloat = TappedSpacing.xxxl + TappedSpacing.lg

    private var imageURL: URL? { user.profilePicture.flatMap(URL.init(string:)) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            artwork
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { if let imageURL { onTapImage?(imageURL) } }
                .accessibilityAddTraits(imageURL == nil ? [] : .isButton)
                .accessibilityLabel("profile photo")

            LinearGradient(colors: [.clear, .black.opacity(0.15), .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: TappedSpacing.xs) {
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, TappedSpacing.sm)
                        .padding(.vertical, TappedSpacing.xs)
                        .glassEffect(.regular, in: Capsule())
                }
                Text(user.displayName)
                    .font(.largeTitle.weight(.heavy))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("@\(user.username.username)")
                    .font(.headline)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, TappedSpacing.lg)
            .padding(.bottom, Self.statsOverlap + TappedSpacing.lg)
        }
        .frame(height: Self.height)
        .stretchyHeader()
    }

    @ViewBuilder private var artwork: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [TappedColors.accent.opacity(0.9), TappedColors.accent.opacity(0.35), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials)
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private var initials: String {
        String(user.displayName.split(separator: " ").prefix(2).compactMap(\.first)).lowercased()
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
