import AppIntents
import Foundation
import TappedDomain

/// Live Activity "Directions" button: opens Apple Maps at the venue coordinates.
struct OpenVenueDirectionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Directions to Venue"
    static let isDiscoverable = false

    @Parameter(title: "Venue") var venueName: String
    @Parameter(title: "Latitude") var latitude: Double
    @Parameter(title: "Longitude") var longitude: Double

    init() {}

    init(gig: GigNight) {
        venueName = gig.venueName
        latitude = gig.latitude ?? 0
        longitude = gig.longitude ?? 0
    }

    var url: URL? {
        GigNight(bookingId: "", venueName: venueName, latitude: latitude, longitude: longitude, startTime: .now, endTime: .now).directionsURL
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        guard let url else { return .result() }
        return .result(opensIntent: OpenURLIntent(url))
    }
}

/// A star in the post-set "how was <Venue>?" prompt: opens the booking's review with the rating filled in.
struct RateGigIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Rate Gig"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Booking") var bookingId: String
    @Parameter(title: "Rating") var rating: Int

    init() {}

    init(bookingId: String, rating: Int) {
        self.bookingId = bookingId
        self.rating = rating
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !TAPPED_WIDGET_EXTENSION
        GigNightCoordinator.shared.rate(bookingId: bookingId, rating: rating)
        #endif
        return .result()
    }
}
