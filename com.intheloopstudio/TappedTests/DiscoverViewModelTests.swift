import Foundation
import TappedData
import TappedDomain
import Testing
@testable import Tapped

@MainActor
@Suite("DiscoverViewModel")
struct DiscoverViewModelTests {
    static let rvaBounds = GeoBounds(swLatitude: 37.48, swLongitude: -77.50, neLatitude: 37.60, neLongitude: -77.37)
    static let elsewhere = GeoBounds(swLatitude: 40.0, swLongitude: -74.1, neLatitude: 40.1, neLongitude: -74.0)

    func makeModel(
        claims: [CustomClaim] = [],
        dependencies: Dependencies? = nil
    ) -> DiscoverViewModel {
        DiscoverViewModel(
            dependencies: dependencies ?? .mock(signedIn: true),
            currentUser: Samples.performer,
            claims: claims,
            now: { Samples.referenceDate }
        )
    }

    @Test func performersDefaultToGigsAndBookersToVenues() {
        let performer = makeModel()
        #expect(performer.overlay == .gigs)
        #expect(performer.isPerformerFirst)
        let booker = makeModel(claims: [.booker])
        #expect(booker.overlay == .venues)
        #expect(!booker.isPerformerFirst)
        #expect(DiscoverViewModel.defaultOverlay(for: Samples.venues[0], claims: []) == .venues)
    }

    @Test func shellStartHoldsTheMapSearchAndRailsUntilStarted() async {
        let model = DiscoverViewModel(
            dependencies: .mock(signedIn: true),
            currentUser: Samples.performer,
            defersStart: true,
            now: { Samples.referenceDate }
        )
        await model.mapRegionChanged(to: Self.rvaBounds)
        #expect(model.searchedBounds == nil)
        #expect(model.opportunityHits.isEmpty)
        #expect(model.featuredPerformers.isEmpty)

        await model.start()
        #expect(model.searchedBounds == Self.rvaBounds)
        #expect(!model.opportunityHits.isEmpty)
        #expect(!model.featuredPerformers.isEmpty)

        await model.start()
        await model.mapRegionChanged(to: Self.elsewhere)
        #expect(model.resultsExpired)
    }

    @Test func performerHeaderAnswersIsThereWork() async {
        let model = makeModel()
        await model.mapRegionChanged(to: Self.rvaBounds)
        let gigs = model.opportunityHits.count
        #expect(gigs > 0)
        #expect(model.gigsHeadline == "\(gigs) open \(gigs == 1 ? "gig" : "gigs") near you")
        #expect(model.venuesHeadline.contains("booking"))
        #expect(model.venueHits.count == Samples.venues.count)
        #expect(model.annotations.allSatisfy { $0.kind == .gig })
        let week = Samples.referenceDate.addingTimeInterval(7 * 24 * 60 * 60)
        #expect(model.paidGigsThisWeek.allSatisfy { $0.isPaid && $0.startTime >= Samples.referenceDate && $0.startTime < week })
        #expect(Set(model.goodFitVenues.map(\.id)) == ["venue-canal", "venue-balliceaux"])
    }

    @Test func firstRegionChangeSearchesVenues() async {
        let model = makeModel(claims: [.booker])
        await model.mapRegionChanged(to: Self.rvaBounds)
        #expect(model.venueHits.count == Samples.venues.count)
        #expect(model.headerTitle == "\(Samples.venues.count) venues nearby")
        #expect(model.annotations.count == Samples.venues.count)
        #expect(!model.resultsExpired)
    }

    @Test func movingTheMapExpiresResultsUntilSearchThisArea() async {
        let model = makeModel(claims: [.booker])
        await model.mapRegionChanged(to: Self.rvaBounds)
        await model.mapRegionChanged(to: Self.elsewhere)
        #expect(model.resultsExpired)
        #expect(model.venueHits.count == Samples.venues.count)

        await model.searchThisArea()
        #expect(!model.resultsExpired)
        #expect(model.venueHits.isEmpty)
        #expect(model.headerTitle == "0 venues nearby")
    }

    @Test func switchingToGigsSearchesOpportunities() async {
        let model = makeModel(claims: [.booker])
        await model.mapRegionChanged(to: Self.rvaBounds)
        await model.select(.gigs)
        #expect(model.overlay == .gigs)
        #expect(!model.opportunityHits.isEmpty)
        #expect(model.headerTitle.hasSuffix(model.opportunityHits.count == 1 ? "gig nearby" : "gigs nearby"))
        #expect(model.annotations.allSatisfy { $0.kind == .gig })
    }

    @Test func goodFitVenuesSortFirst() async {
        let model = makeModel()
        await model.mapRegionChanged(to: Self.rvaBounds)
        let sorted = model.sortedVenueHits
        let fits = sorted.prefix { model.isGoodFit($0) }
        #expect(Set(fits.map(\.id)) == ["venue-canal", "venue-balliceaux"])
        #expect(sorted.count == model.venueHits.count)
    }

    @Test func genreCountsAreLowercasedAndSortedByFrequency() async {
        let model = makeModel()
        await model.mapRegionChanged(to: Self.rvaBounds)
        let counts = model.genreCounts
        #expect(counts.first?.genre == Genre.rock.rawValue.lowercased())
        #expect(counts.first?.count == 4)
        #expect(zip(counts, counts.dropFirst()).allSatisfy { $0.count >= $1.count })
    }

    @Test func filtersDoNotAddASecondSubscriptionGate() async {
        let free = makeModel()
        await free.mapRegionChanged(to: Self.rvaBounds)
        #expect(await free.applyFilters(genres: [.jazz], capacity: 0...1000))
        #expect(free.genreFilters == [.jazz])

        let premium = makeModel()
        await premium.mapRegionChanged(to: Self.rvaBounds)
        #expect(await premium.applyFilters(genres: [.jazz], capacity: 0...1000))
        #expect(premium.genreFilterLabel == "1 genre")
        #expect(premium.venueHits.allSatisfy { $0.venueInfo?.genres.contains(Genre.jazz.rawValue) == true })
    }

    @Test func loadPopulatesFeaturedSectionsAndTasks() async {
        let model = makeModel()
        await model.load()
        #expect(!model.featuredPerformers.isEmpty)
        #expect(!model.featuredOpportunities.isEmpty)
        #expect(model.contactedVenuesCount == 0)
        #expect(model.incompleteTaskCount >= 1)
        #expect(model.tasksBannerMessage?.hasSuffix("left to get booked") == true)
        model.isTasksBannerDismissed = true
        #expect(model.tasksBannerMessage == nil)
    }

    @Test func addGigQuickActionRequiresBookerOrAdmin() {
        #expect(makeModel().quickActions.isEmpty)
        #expect(makeModel(claims: [.booker]).quickActions.map(\.route) == [.admin])
    }

    @Test func locateIssuesFreshCameraRequests() {
        let model = makeModel()
        model.locate()
        let first = model.cameraRequest
        #expect(first?.kind == .center(Samples.performer.location ?? .rva, spanDegrees: DiscoverViewModel.defaultSpanDegrees))
        model.locate()
        #expect(model.cameraRequest?.id != first?.id)
    }

    @Test func annotationRoutes() async {
        let model = makeModel()
        await model.mapRegionChanged(to: Self.rvaBounds)
        let venue = Samples.venues[0]
        #expect(model.route(forAnnotation: venue.id) == .profile(userId: venue.id, user: venue))
        #expect(model.route(forAnnotation: "missing") == nil)
    }
}
