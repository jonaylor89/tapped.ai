import SwiftUI
import TappedUI

/// Form header used by login/signup/forgot password.
struct AuthHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TappedSpacing.sm) {
            Image("TappedLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 40)
                .accessibilityHidden(true)
            Text(title)
                .font(TappedTypography.headingLg)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(TappedTypography.bodyMd)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: TappedSpacing.lg, leading: TappedSpacing.xs, bottom: TappedSpacing.sm, trailing: 0))
    }
}

/// Sign in with Apple / Google rows. Styled per Apple's HIG (system-drawn logo, black/white) rather
/// than the stock `SignInWithAppleButton` because the credential flow lives in `AuthRepository`.
struct SocialSignInButtons: View {
    let isDisabled: Bool
    let apple: () -> Void
    let google: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: TappedSpacing.md) {
            Button(action: apple) {
                Label("continue with apple", systemImage: "apple.logo")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
            }
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())

            Button(action: google) {
                Label("continue with google", systemImage: "g.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
            }
            .buttonStyle(.glass)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

/// Full-width primary action inside a `Form`.
struct AuthSubmitButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView() }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: GlassMetrics.control)
        }
        .buttonStyle(.glassProminent)
        .tint(TappedColors.accent)
        .disabled(!isEnabled)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }
}

#Preview("auth components") {
    Form {
        AuthHeader("welcome back", subtitle: "log in to keep getting booked")
        Section { AuthSubmitButton(title: "log in", isLoading: false, isEnabled: true) {} }
        Section { SocialSignInButtons(isDisabled: false, apple: {}, google: {}) }
    }
}
