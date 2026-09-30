import SwiftUI
import TappedData
import TappedUI

extension Route {
    /// `self` for premium users, `.paywall` for everyone else (`PremiumBuilder` in Flutter).
    func requiringPremium(_ isPremium: Bool) -> Route {
        isPremium ? self : .paywall
    }
}

extension Router {
    /// Pushes `route` for premium users and the paywall for everyone else.
    func push(_ route: Route, requiresPremium isPremium: Bool) {
        push(route.requiringPremium(isPremium))
    }
}

/// Shows `content` to premium users; otherwise an upsell banner that opens the paywall.
/// Reads `AppSession.isPremium`, which follows `PurchasesRepository.entitlementUpdates()`.
struct PremiumGate<Content: View>: View {
    let title: String
    let message: String?
    @ViewBuilder let content: () -> Content

    @Environment(AppSession.self) private var session
    @Environment(Router.self) private var router

    init(_ title: String = "upgrade to unlock", message: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.message = message
        self.content = content
    }

    var body: some View {
        if session.isPremium {
            content()
        } else {
            GlassBanner(title, message: message, systemImage: "crown.fill") {
                router.push(.paywall)
            }
            .accessibilityHint("opens tapped premium")
        }
    }
}

#Preview {
    let dependencies = Dependencies.mock(signedIn: true)
    PremiumGate("upgrade to message", message: "talk directly to venues") {
        Text("premium content")
    }
    .padding()
    .background(PreviewBackdrop())
    .environment(AppSession(dependencies: dependencies))
    .environment(Router())
}
