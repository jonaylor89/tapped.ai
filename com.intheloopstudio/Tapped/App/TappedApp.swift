import SwiftUI
import TappedData
import TappedUI

@main
struct TappedApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: AppSession
    @State private var router = Router()
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    private let dependencies: Dependencies
    private let inbound = AppEnvironment.inbound

    init() {
        let dependencies = AppEnvironment.dependencies
        self.dependencies = dependencies
        let launchOptions = LaunchOptions.current
        _session = State(initialValue: AppSession(dependencies: dependencies, launchOptions: launchOptions))
        if let link = launchOptions.link {
            AppEnvironment.inbound.open(link)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
                .environment(session)
                .environment(router)
                .environment(inbound)
                .tint(TappedColors.accent)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    // Universal links and the custom scheme arrive here on both cold and warm start.
                    if FirebaseBootstrap.handle(url: url) { return }
                    inbound.open(url)
                }
        }
    }
}

/// Resolved once per process so the app delegate and the scene share the same mode.
enum AppEnvironment {
    @MainActor static let dependencies = Dependencies.resolve()
    @MainActor static let inbound = InboundLinks()
}
