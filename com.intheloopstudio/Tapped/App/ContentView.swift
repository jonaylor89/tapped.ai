import SwiftUI
import TappedData
import TappedUI

/// Gates: maintenance / update required → Splash → Login/Signup → confirm email → onboarding → main shell.
struct ContentView: View {
    @Environment(AppSession.self) private var session
    @Environment(InboundLinks.self) private var inbound: InboundLinks?
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

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
                case let .updateRequired(minimum):
                    UpdateRequiredView(minimumVersion: minimum) { openURL(AppStoreLink.url) }
                case .signedOut:
                    AuthFlowView()
                case let .confirmEmail(authUser):
                    NavigationStack { ConfirmEmailView(dependencies: dependencies, authUser: authUser) }
                        .id(authUser.uid)
                case let .onboarding(uid):
                    OnboardingView(dependencies: dependencies, initialStep: session.launchOptions.onboardingStep)
                        .id(uid)
                case let .signedIn(user):
                    if session.availableUpdate == nil {
                        ShellView(
                            currentUser: user,
                            dependencies: dependencies,
                            isPremium: session.isPremium,
                            claims: session.claims,
                            launchOptions: session.launchOptions
                        )
                        .id(user.id)
                    } else {
                        SplashView()
                    }
                }
            }
        }
        .animation(GlassMotion.ease, value: session.phase)
        .task { await session.run() }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await dependencies.notifications.setBadgeCount(0) }
        }
        .onChange(of: inbound?.apnsRegistrations) {
            Task { await session.saveDeviceTokenIfSignedIn() }
        }
        .alert("update available", isPresented: updatePromptBinding) {
            Button("update now") {
                session.dismissUpdate(ignoreVersion: false)
                openURL(AppStoreLink.url)
            }
            Button("later", role: .cancel) { session.dismissUpdate(ignoreVersion: false) }
            Button("ignore") { session.dismissUpdate(ignoreVersion: true) }
        } message: {
            Text("tapped \(session.availableUpdate ?? "") is available. you have \(session.appVersion.description).")
        }
    }

    /// The shell (and its Discover sheet) stays behind the splash until the prompt is answered.
    private var updatePromptBinding: Binding<Bool> {
        Binding(
            get: { session.availableUpdate != nil && session.currentUser != nil },
            set: { if !$0 { session.dismissUpdate(ignoreVersion: false) } }
        )
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

#Preview("onboarding") {
    let dependencies = Dependencies.mock(onboarding: true)
    ContentView()
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}

#Preview("update required") {
    let dependencies = Dependencies.mock(minimumAppVersion: "99.0.0")
    ContentView()
        .environment(\.dependencies, dependencies)
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}
