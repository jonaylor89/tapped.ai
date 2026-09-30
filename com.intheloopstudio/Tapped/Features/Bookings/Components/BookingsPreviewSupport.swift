import SwiftUI
import TappedData
import TappedDomain

extension View {
    /// Mock dependencies + router for session-3 previews.
    func bookingsPreview(dark: Bool = false) -> some View {
        NavigationStack { self }
            .environment(\.dependencies, .mock(signedIn: true))
            .environment(Router())
            .preferredColorScheme(dark ? .dark : .light)
    }
}
