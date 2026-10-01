import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("Search")
struct SearchViewModelTests {
    func makeRecents() -> RecentSearches {
        RecentSearches(defaults: UserDefaults(suiteName: "tests.\(UUID().uuidString)")!)
    }

    func makeModel(recents: RecentSearches? = nil) -> SearchViewModel {
        SearchViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer, recents: recents ?? makeRecents(), debounce: .zero)
    }

    @Test func recentSearchesDedupeLowercaseAndCap() {
        let recents = makeRecents()
        recents.record("Camel")
        recents.record("  ")
        recents.record("nova")
        recents.record("camel")
        #expect(recents.terms == ["camel", "nova"])
        for index in 0..<20 { recents.record("term \(index)") }
        #expect(recents.terms.count == RecentSearches.limit)
        #expect(recents.remove("term 19").first == "term 18")
        recents.clear()
        #expect(recents.terms.isEmpty)
    }

    @Test func typingSearchesAfterDebounce() async {
        let model = makeModel()
        #expect(model.isIdle)
        model.query = "camel"
        #expect(model.isSearching)
        await model.waitForSearch()
        #expect(model.results.map(\.id).contains("venue-camel"))
        #expect(!model.isSearching)
    }

    @Test func venueScopeOnlyReturnsVenues() async {
        let model = makeModel()
        model.scope = .venues
        model.query = "a"
        await model.waitForSearch()
        #expect(!model.results.isEmpty)
        #expect(model.results.allSatisfy { $0.isVenue })
    }

    @Test func clearingTheQueryReturnsToIdle() async {
        let model = makeModel()
        model.query = "camel"
        await model.waitForSearch()
        model.query = ""
        #expect(model.isIdle)
        #expect(model.results.isEmpty)
    }

    @Test func submittingRecordsARecentSearch() async {
        let recents = makeRecents()
        let model = makeModel(recents: recents)
        model.query = "Nova"
        model.submit()
        #expect(model.recentSearches == ["nova"])
        #expect(recents.terms == ["nova"])
        model.removeRecent("nova")
        #expect(model.recentSearches.isEmpty)
    }

    @Test func nearbyOpportunitiesLoad() async {
        let model = makeModel()
        await model.loadNearby()
        #expect(!model.nearbyOpportunities.isEmpty)
    }
}

@MainActor
@Suite("Advanced search + location form")
struct AdvancedSearchTests {
    @Test func venueSearchUsesVenueGenresAndCapacity() {
        let model = AdvancedSearchViewModel(dependencies: .mock())
        model.occupations = [.venue]
        model.genres = [.funk, .dance]
        model.minCapacity = 100
        model.maxCapacity = 500
        let filters = model.filters
        #expect(filters.occupations == ["Venue", "venue"])
        #expect(filters.venueGenres == [Genre.dance.rawValue, Genre.funk.rawValue].sorted())
        #expect(filters.genres == nil)
        #expect(filters.minCapacity == 100)
        #expect(filters.maxCapacity == 500)
    }

    @Test func performerSearchIgnoresCapacity() {
        let model = AdvancedSearchViewModel(dependencies: .mock())
        model.genres = [.funk]
        model.maxCapacity = 200
        #expect(model.filters.genres == [Genre.funk.rawValue])
        #expect(model.filters.maxCapacity == nil)
        #expect(model.hasFilters)
        model.clear()
        #expect(!model.hasFilters)
        #expect(model.filters == UserSearchFilters())
    }

    @Test func runSearchFindsVenuesNearAPlace() async {
        let model = AdvancedSearchViewModel(dependencies: .mock())
        model.occupations = [.venue]
        model.place = MockPlacesRepository.places[0]
        await model.runSearch()
        #expect(!model.results.isEmpty)
        #expect(model.results.allSatisfy { $0.isVenue })

        model.place = MockPlacesRepository.places[1]
        await model.runSearch()
        #expect(model.results.allSatisfy { $0.location?.placeId != Location.rva.placeId })
    }

    @Test func locationFormAutocompletesAndResolves() async throws {
        let model = LocationFormViewModel(dependencies: .mock(), initialPlace: nil, debounce: .zero)
        model.query = "rich"
        await model.waitForSearch()
        let prediction = try #require(model.predictions.first)
        #expect(prediction.primaryText == "Richmond")
        let place = await model.resolve(prediction)
        #expect(place?.placeId == Location.rva.placeId)
    }
}

@MainActor
@Suite("Gig search")
struct GigSearchViewModelTests {
    func makeModel(isPremium: Bool = true) -> GigSearchViewModel {
        GigSearchViewModel(dependencies: .mock(signedIn: true, isPremium: isPremium), currentUser: Samples.performer, isPremium: isPremium)
    }

    @Test func defaultsComeFromThePerformer() {
        let model = makeModel()
        #expect(Set(model.genres.map(\.rawValue)) == Set(Samples.performer.performerInfo?.genres ?? []))
        #expect(model.maxCapacity <= GigSearchViewModel.capacityLimit)
    }

    @Test func maxedCapacitySliderMeansUnbounded() {
        let model = makeModel()
        model.minCapacity = 50
        model.maxCapacity = GigSearchViewModel.capacityLimit
        #expect(model.capacityBounds() == 50...GigSearchViewModel.unboundedCapacity)
        model.maxCapacity = 400
        #expect(model.capacityBounds() == 50...400)
    }

    @Test func freeUsersArePaywalled() async {
        #expect(await makeModel(isPremium: false).searchVenues() == .needsPremium)
    }

    @Test func validatesGenresAndPlace() async {
        let model = makeModel()
        model.genres = []
        #expect(await model.searchVenues() == .invalid("please select at least one genre"))
        model.genres = [.funk]
        #expect(await model.searchVenues() == .invalid("please select a city"))
    }

    @Test func resultsAreSortedGoodFitsFirst() async {
        let model = makeModel()
        await model.loadInitialPlace()
        #expect(model.place?.placeId == Samples.performer.location?.placeId)
        model.maxCapacity = GigSearchViewModel.capacityLimit
        #expect(await model.searchVenues() == .results)
        #expect(!model.results.isEmpty)
        let fits = model.results.map { model.fit(for: $0).isGoodFit }
        #expect(fits == fits.sorted { $0 && !$1 })

        model.selectAll(true)
        #expect(model.allSelected)
        model.toggle(model.results[0])
        #expect(model.selectedVenues.count == model.results.count - 1)
    }
}

@MainActor
@Suite("Opportunities")
struct OpportunityTests {
    let opportunity = Samples.opportunities[0]

    @Test func freeUsersSpendQuotaThenHitThePaywall() async throws {
        let dependencies = Dependencies.mock(signedIn: true)
        let application = OpportunityApplication(dependencies: dependencies, userId: Samples.performer.id, isPremium: false)
        let startingQuota = try #require(await application.remainingQuota())
        #expect(try await application.apply(to: [opportunity], comment: "hi") == .applied)
        #expect(await application.remainingQuota() == startingQuota - 1)
        #expect(try await dependencies.database.isUserAppliedForOpportunity(opportunityId: opportunity.id, userId: Samples.performer.id))
        let tooMany = Array(repeating: opportunity, count: startingQuota)
        #expect(try await application.apply(to: tooMany, comment: "") == .needsPremium)
    }

    @Test func premiumIsUnlimited() async throws {
        let dependencies = Dependencies.mock(signedIn: true, isPremium: true)
        let application = OpportunityApplication(dependencies: dependencies, userId: Samples.performer.id, isPremium: true)
        #expect(await application.remainingQuota() == nil)
        #expect(try await application.apply(to: Samples.opportunities, comment: "") == .applied)
    }

    @Test func applyingNotifiesTheVenues() async throws {
        let notifications = MockOpportunityNotificationRepository()
        var dependencies = Dependencies.mock(signedIn: true)
        dependencies.opportunityNotifications = notifications
        let application = OpportunityApplication(dependencies: dependencies, userId: Samples.performer.id, isPremium: false)
        let opportunities = Array(Samples.opportunities.prefix(2))
        #expect(try await application.apply(to: opportunities, comment: "pick me") == .applied)
        #expect(await notifications.venueNotifications == [
            .init(opportunityIds: opportunities.map(\.id), note: "pick me"),
        ])
    }

    @Test func detailLoadsVenueAndApplies() async {
        let model = OpportunityViewModel(
            dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: false, claims: [],
            opportunityId: opportunity.id, opportunity: nil
        )
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.venue != nil)
        #expect(model.canApply)
        #expect(!model.canSeeApplicants)
        #expect(!model.isApplied)
        #expect(await model.apply(comment: "  see you there ") == .applied)
        #expect(model.isApplied)
    }

    @Test func missingOpportunityIsNotFound() async {
        let model = OpportunityViewModel(
            dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: false, claims: [],
            opportunityId: "nope", opportunity: nil
        )
        await model.load()
        #expect(model.phase == .notFound)
    }

    @Test func ownersAndAdminsSeeApplicants() async {
        let owner = OpportunityViewModel(
            dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: false, claims: [.admin],
            opportunityId: opportunity.id, opportunity: opportunity
        )
        #expect(owner.canSeeApplicants)
        let applicants = InterestedUsersViewModel(dependencies: .mock(), opportunity: opportunity)
        await applicants.load()
        #expect(Set(applicants.users.map(\.id)) == Set(Samples.applicants[opportunity.id] ?? []))
    }

    @Test func batchApplyMarksAppliedAndExitsSelection() async {
        let model = OpportunitiesListViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer, isPremium: true, opportunities: Samples.opportunities)
        await model.load()
        #expect(model.appliedIds.isEmpty)
        model.isSelecting = true
        model.toggle(model.opportunities[0])
        model.toggle(model.opportunities[1])
        #expect(await model.applySelected() == .applied)
        #expect(model.appliedIds == Set(model.opportunities.prefix(2).map(\.id)))
        #expect(!model.isSelecting)
        #expect(model.selectedIds.isEmpty)
    }

    @Test func feedAdvancesAndRemembersSwipes() async {
        let dependencies = Dependencies.mock(signedIn: true, isPremium: true)
        let model = OpportunityFeedViewModel(dependencies: dependencies, currentUser: Samples.performer, isPremium: true)
        await model.load()
        let first = model.current
        #expect(first != nil)
        await model.perform(.dislike)
        #expect(model.current?.id != first?.id)
        #expect(await model.perform(.apply) == .applied)
        #expect(model.appliedCount == 1)

        let reloaded = OpportunityFeedViewModel(dependencies: dependencies, currentUser: Samples.performer, isPremium: true)
        await reloaded.load()
        #expect(reloaded.opportunities.count == model.opportunities.count - 2)
    }

    @Test func feedIsCaughtUpWhenEmpty() async {
        let model = OpportunityFeedViewModel(dependencies: .mock(signedIn: true, isPremium: true), currentUser: Samples.performer, isPremium: true)
        await model.load()
        while model.current != nil { await model.perform(.dismiss) }
        #expect(model.isCaughtUp)
    }
}

@MainActor
@Suite("Reviews")
struct UserReviewsViewModelTests {
    static let reviewedBy: Set<String> = Set(Samples.performerReviews.map(\.fields.bookerId))

    @Test func loadsReviewsNewestFirstWithReviewers() async {
        let model = UserReviewsViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performer, userId: Samples.performer.id)
        await model.load()
        let expected = Samples.performerReviews.filter { $0.fields.performerId == Samples.performer.id }
        #expect(model.reviews.count == expected.count)
        #expect(model.reviews.map(\.fields.timestamp) == model.reviews.map(\.fields.timestamp).sorted(by: >))
        #expect(model.reviews.allSatisfy { model.reviewer(for: $0) != nil })
        #expect(model.averageRating != nil)
        #expect(!model.canWriteReview)
    }

    @Test func venueReviewsAreBookerReviews() async {
        let model = UserReviewsViewModel(dependencies: .mock(signedIn: true), currentUser: Samples.performers[1], userId: "venue-camel")
        await model.load()
        #expect(model.reviewType == .booker)
        #expect(model.reviews.allSatisfy { $0.type == .booker })
    }

    @Test func writingAReviewPrependsIt() async throws {
        let venue = try #require(Samples.venues.first { !Self.reviewedBy.contains($0.id) })
        let model = UserReviewsViewModel(dependencies: .mock(signedIn: true), currentUser: venue, userId: Samples.performer.id)
        await model.load()
        #expect(model.canWriteReview)
        #expect(model.reviewType == .performer)
        #expect(await model.submit(rating: 4, text: " solid set "))
        let review = try #require(model.reviews.first)
        #expect(review.fields.bookerId == venue.id)
        #expect(review.fields.overallReview == "solid set")
        #expect(model.reviewer(for: review)?.id == venue.id)
        #expect(!model.canWriteReview)
    }
}

@Suite("Session 4 routes")
struct SearchOpportunitiesRouteTests {
    @Test func mockLaunchPaths() {
        #expect(Route.mockLaunchPath("search") == [.search])
        #expect(Route.mockLaunchPath("opportunity-feed") == [.opportunityFeed])
        #expect(Route.mockLaunchPath("nope") == nil)
        let options = LaunchOptions.from(["TAPPED_MOCK": "1", "TAPPED_MOCK_ROUTE": "gig-search", "TAPPED_MOCK_ROUTE_DETAIL": "1"])
        #expect(options.routes == [.gigSearch])
        #expect(options.routeDetail == "1")
        #expect(LaunchOptions.from(["TAPPED_MOCK_ROUTE": "search"]).routes.isEmpty)
    }

    @Test func nativeRoutesBelongToSession4() {
        #expect(Route.opportunities([]).owner == 4)
        #expect(Route.opportunityFeed.owner == 4)
    }
}
