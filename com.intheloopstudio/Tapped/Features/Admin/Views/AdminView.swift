import SwiftUI
import TappedData
import TappedDomain
import TappedUI

/// `lib/ui/admin/admin_view.dart`: admin-only gate around `CreateOpportunityForm`.
struct AdminView: View {
    let dependencies: Dependencies
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if session.claims.contains(.admin), let user = session.currentUser {
                CreateOpportunityForm(dependencies: dependencies, currentUserId: user.id)
            } else {
                GlassEmptyState(
                    "admins only",
                    message: "you need the admin role to post gigs",
                    systemImage: "lock.fill"
                )
                .padding(GlassMetrics.edgeInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TappedColors.background.ignoresSafeArea())
            }
        }
        .navigationTitle("new opportunity")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("admin") {
    let dependencies = Dependencies.mock(signedIn: true, claims: [.admin])
    let session = AppSession(dependencies: dependencies)
    NavigationStack { AdminView(dependencies: dependencies) }
        .environment(session)
        .environment(Router())
        .task { await session.run() }
}

#Preview("not admin") {
    let dependencies = Dependencies.mock(signedIn: true)
    NavigationStack { AdminView(dependencies: dependencies) }
        .environment(AppSession(dependencies: dependencies))
        .environment(Router())
}
