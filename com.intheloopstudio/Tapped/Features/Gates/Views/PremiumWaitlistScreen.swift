import SwiftUI
import TappedData
import TappedUI

struct PremiumWaitlistScreen: View {
    @State private var model: PremiumWaitlistViewModel

    init(dependencies: Dependencies, userId: String) {
        _model = State(initialValue: PremiumWaitlistViewModel(dependencies: dependencies, userId: userId))
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView()
            } else {
                WaitlistView(isOnWaitlist: model.isOnWaitlist) { Task { await model.join() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TappedColors.background.ignoresSafeArea())
        .animation(GlassMotion.ease, value: model.isOnWaitlist)
        .navigationTitle(Route.paywall.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .alert("uh oh", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("ok", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack { PremiumWaitlistScreen(dependencies: .mock(signedIn: true), userId: "performer-nova") }
}

#Preview("dark") {
    NavigationStack { PremiumWaitlistScreen(dependencies: .mock(signedIn: true), userId: "performer-nova") }
        .preferredColorScheme(.dark)
}
