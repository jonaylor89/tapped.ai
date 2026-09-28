import SwiftUI
import TappedUI

/// "view all" list for the current overlay.
struct DiscoverAllResultsView: View {
    let model: DiscoverViewModel
    let push: (Route) -> Void

    var body: some View {
        NavigationStack {
            List {
                switch model.overlay {
                case .venues:
                    ForEach(model.sortedVenueHits) { venue in
                        Button { push(.profile(userId: venue.id, user: venue)) } label: {
                            UserTile(user: venue, subtitle: VenueRow.subtitle(venue)) {
                                if model.isGoodFit(venue) {
                                    Text("for you").font(.body.weight(.bold)).foregroundStyle(TappedColors.success)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                case .gigs:
                    ForEach(model.opportunityHits) { gig in
                        Button { push(.opportunity(opportunityId: gig.id, opportunity: gig)) } label: {
                            OpportunityRow(opportunity: gig)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle(model.overlay == .venues ? "venues" : "gigs")
            .navigationSubtitle(model.headerTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
