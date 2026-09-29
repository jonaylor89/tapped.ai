import Testing
@testable import TappedDomain

@Suite("VenueFit (venue_fit_utils.dart)")
struct VenueFitTests {
    let performer = Samples.performer.performerInfo

    @Test func fitNeedsCapacityAndSharedGenre() throws {
        let performer = try #require(performer)
        for venue in Samples.venues {
            let fit = VenueFit(venue: venue, performer: performer)
            if let capacity = venue.venueInfo?.capacity {
                #expect(fit.capacityFits == (performer.category.suggestedMaxCapacity >= capacity))
            } else {
                #expect(!fit.capacityFits)
            }
            #expect(fit.isGoodFit == (fit.capacityFits && !fit.sharedGenres.isEmpty))
        }
    }

    @Test func noPerformerIsNeverAFit() {
        #expect(Samples.venues.allSatisfy { !VenueFit(venue: $0, performer: nil).isGoodFit })
    }

    @Test func sortingIsStableGoodFitsFirst() {
        let sorted = VenueFit.sorted(Samples.venues, for: performer)
        let fits = sorted.map { VenueFit(venue: $0, performer: performer).isGoodFit }
        #expect(fits == fits.sorted { $0 && !$1 })
        #expect(Set(sorted.map(\.id)) == Set(Samples.venues.map(\.id)))
        let goodInOriginalOrder = Samples.venues.filter { VenueFit(venue: $0, performer: performer).isGoodFit }.map(\.id)
        #expect(Array(sorted.prefix(goodInOriginalOrder.count).map(\.id)) == goodInOriginalOrder)
        #expect(!goodInOriginalOrder.isEmpty)
    }
}
