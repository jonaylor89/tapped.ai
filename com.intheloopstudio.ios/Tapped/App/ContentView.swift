import SwiftUI
import TappedData
import TappedUI

/// Auth gate: Splash → Login/Signup → main shell.
struct ContentView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        Group {
            if let screen = session.launchOptions.screen {
                AuthFlowView(initialScreen: screen)
            } else {
                switch session.phase {
                case .splash:
                    SplashView()
                case .maintenance:
                    MaintenanceView()
                case .signedOut:
                    AuthFlowView()
                case .onboarding:
                    // TODO(session-5): replace with the onboarding flow.
                    NavigationStack { PlaceholderScreen(title: Route.onboarding.title) }
                case let .signedIn(user):
                    ShellView(currentUser: user, chat: dependencies.chat)
                        .id(user.id)
                }
            }
        }
        .animation(GlassMotion.ease, value: session.phase)
        .task { await session.run() }
    }
}

#Preview("signed out") {
    let dependencies = Dependencies.mock()
    ContentView()
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}

#Preview("signed in") {
    let dependencies = Dependencies.mock(signedIn: true)
    ContentView()
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}
