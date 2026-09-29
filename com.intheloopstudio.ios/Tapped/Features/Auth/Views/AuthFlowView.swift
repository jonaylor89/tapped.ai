import SwiftUI
import TappedData

/// Signed-out navigation: Splash landing → login / signup / forgot password.
struct AuthFlowView: View {
    @State private var path: [Route]

    init(initialScreen: LaunchOptions.Screen? = nil) {
        let path: [Route] = switch initialScreen {
        case .login: [.login]
        case .signup: [.signUp]
        case .forgot: [.login, .forgotPassword]
        case .splash, nil: []
        }
        _path = State(initialValue: path)
    }

    var body: some View {
        NavigationStack(path: $path) {
            SplashView(isLoading: false, getStarted: { path.append(.signUp) }, logIn: { path.append(.login) })
                .toolbarVisibility(.hidden, for: .navigationBar)
                .tappedRouteDestinations()
        }
    }
}

#Preview {
    AuthFlowView()
        .environment(\.dependencies, .mock())
}
