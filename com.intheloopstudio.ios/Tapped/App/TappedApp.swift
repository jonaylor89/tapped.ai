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

    init() {
        let dependencies = AppEnvironment.dependencies
        self.dependencies = dependencies
        _session = State(initialValue: AppSession(dependencies: dependencies, launchOptions: .current))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.dependencies, dependencies)
                .environment(session)
                .environment(router)
                .tint(TappedColors.accent)
                .preferredColorScheme(appearance.colorScheme)
                .onOpenURL { url in
                    _ = FirebaseBootstrap.handle(url: url)
                }
        }
    }
}

/// Resolved once per process so the app delegate and the scene share the same mode.
enum AppEnvironment {
    @MainActor static let dependencies = Dependencies.resolve()
}
