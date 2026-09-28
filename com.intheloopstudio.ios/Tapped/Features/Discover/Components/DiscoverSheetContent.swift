import SwiftUI
import TappedData
import TappedUI

/// Contents of the Discover `MapsStyleSheet` (`DraggableSheet` children in Flutter).
struct DiscoverSheetContent: View {
    @Bindable var model: DiscoverViewModel
    @Environment(\.dependencies) private var dependencies
    let push: (Route) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SheetHeader(title: model.headerTitle, filterLabel: model.genreFilterLabel, isSearching: model.isSearching)
                SheetQuickActions(actions: model.quickActions, push: push)
                SheetSectionHeader(model.overlay == .venues ? "venues" : "gigs")
                SheetResultsSection(model: model, push: push)
                if model.overlay == .venues {
                    SheetGenreChips(counts: model.genreCounts)
                }
                SheetTopPerformers(performers: model.featuredPerformers, isPremium: model.isPremium, push: push)
                SheetFeaturedGigs(opportunities: model.featuredOpportunities, push: push)
            }
            .padding(.bottom, TappedSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(item: $model.modal) { modal in
            switch modal {
            case .filters:
                DiscoverFiltersView(model: model, showPaywall: { model.modal = nil; push(.paywall) })
            case .allResults:
                DiscoverAllResultsView(model: model, push: { route in model.modal = nil; push(route) })
            }
        }
    }
}
