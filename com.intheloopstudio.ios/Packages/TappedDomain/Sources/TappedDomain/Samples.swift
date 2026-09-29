import Foundation

/// Deterministic sample data for previews, mocks and tests. Never used by live code paths.
public enum Samples {
    public static let referenceDate = Date(timeIntervalSince1970: 1_791_000_000)

    public static let performer = UserModel(
        id: "performer-nova",
        timestamp: referenceDate.addingTimeInterval(-2 * 24 * 60 * 60),
        username: "djnova",
        email: "nova@example.com",
        artistName: "DJ Nova",
        profilePicture: nil,
        bio: "house + disco edits. richmond, va.",
        occupations: ["DJ", "Music Producer"],
        location: .rva,
        performerInfo: PerformerInfo(
            genres: [Genre.dance.rawValue, Genre.funk.rawValue],
            rating: 4.8,
            reviewCount: 12,
            bookingCount: 31,
            category: .hometownHero
        ),
        socialFollowing: SocialFollowing(tiktokFollowers: 14_300, instagramHandle: "djnova", instagramFollowers: 8200)
    )

    public static let performers: [UserModel] = [
        performer,
        UserModel(
            id: "performer-lowtide",
            timestamp: referenceDate.addingTimeInterval(-40 * 24 * 60 * 60),
            username: "lowtide",
            artistName: "Low Tide",
            bio: "four-piece indie rock band",
            occupations: ["Band"],
            location: .rva,
            performerInfo: PerformerInfo(genres: [Genre.indiePop.rawValue, Genre.rock.rawValue], rating: 4.6, reviewCount: 5, bookingCount: 14, category: .emerging),
            socialFollowing: SocialFollowing(instagramFollowers: 3100)
        ),
        UserModel(
            id: "performer-mara",
            timestamp: referenceDate.addingTimeInterval(-300 * 24 * 60 * 60),
            username: "maravoss",
            artistName: "Mara Voss",
            bio: "jazz vocalist",
            occupations: ["Performer"],
            location: .rva,
            performerInfo: PerformerInfo(genres: [Genre.jazz.rawValue, Genre.rnb.rawValue], rating: 5, reviewCount: 22, bookingCount: 60, category: .mainstream),
            socialFollowing: SocialFollowing(tiktokFollowers: 90_000, instagramFollowers: 41_000)
        ),
        UserModel(
            id: "performer-kilo",
            timestamp: referenceDate.addingTimeInterval(-90 * 24 * 60 * 60),
            username: "kilo.k",
            artistName: "Kilo K",
            bio: "rapper / songwriter",
            occupations: ["Performer", "Songwriter"],
            location: .rva,
            performerInfo: PerformerInfo(genres: [Genre.hipHop.rawValue, Genre.rapRock.rawValue], rating: 4.2, reviewCount: 3, bookingCount: 7, category: .undiscovered),
            socialFollowing: SocialFollowing(tiktokFollowers: 2200)
        ),
    ]

    private static func venue(
        _ id: String, _ name: String, _ username: String, lat: Double, lng: Double,
        capacity: Int, type: VenueType, genres: [Genre]
    ) -> UserModel {
        UserModel(
            id: id,
            timestamp: referenceDate.addingTimeInterval(-500 * 24 * 60 * 60),
            username: Username(username),
            artistName: name,
            bio: "live music venue",
            occupations: ["Venue"],
            location: Location(placeId: "sample-\(id)", lat: lat, lng: lng),
            venueInfo: VenueInfo(
                bookingEmail: "booking@\(username).com",
                capacity: capacity,
                genres: genres.map(\.rawValue),
                type: type,
                topPerformerIds: performers.map(\.id),
                bookingsByDayOfWeek: [1, 0, 2, 3, 6, 9, 4],
                responseRate: 0.8
            )
        )
    }

    /// Venues around Richmond, VA (the Flutter `DiscoverState` default centre).
    public static let venues: [UserModel] = [
        venue("venue-camel", "The Camel", "thecamel", lat: 37.5511, lng: -77.4570, capacity: 250, type: .bar, genres: [.rock, .indiePop, .punk]),
        venue("venue-national", "The National", "thenational", lat: 37.5415, lng: -77.4380, capacity: 1500, type: .concertHall, genres: [.rock, .pop, .hipHop]),
        venue("venue-broadberry", "The Broadberry", "broadberry", lat: 37.5563, lng: -77.4665, capacity: 800, type: .club, genres: [.indiePop, .electronic]),
        venue("venue-canal", "Canal Club", "canalclub", lat: 37.5341, lng: -77.4300, capacity: 1000, type: .club, genres: [.electronic, .dance]),
        venue("venue-capitalale", "Capital Ale House", "capitalale", lat: 37.5400, lng: -77.4420, capacity: 400, type: .restaurant, genres: [.rock, .country]),
        venue("venue-hardywood", "Hardywood", "hardywood", lat: 37.5647, lng: -77.4588, capacity: 300, type: .brewery, genres: [.folk, .americana]),
        venue("venue-altria", "Altria Theater", "altria", lat: 37.5478, lng: -77.4520, capacity: 3500, type: .theater, genres: [.jazz, .classical]),
        venue("venue-balliceaux", "Balliceaux", "balliceaux", lat: 37.5528, lng: -77.4661, capacity: 150, type: .bar, genres: [.jazz, .rnb, .funk]),
        venue("venue-brown", "Browns Island", "brownsisland", lat: 37.5357, lng: -77.4449, capacity: 6000, type: .festival, genres: [.pop, .rock, .hipHop]),
        venue("venue-vagabond", "Vagabond", "vagabond", lat: 37.5451, lng: -77.4395, capacity: 200, type: .restaurant, genres: [.jazz, .rnb]),
    ]

    public static let opportunities: [Opportunity] = [
        Opportunity(
            id: "op-friday-openers",
            userId: "venue-camel",
            location: venues[0].location ?? .rva,
            timestamp: referenceDate,
            startTime: referenceDate.addingTimeInterval(5 * 24 * 60 * 60),
            endTime: referenceDate.addingTimeInterval(5 * 24 * 60 * 60 + 3 * 60 * 60),
            title: "friday night openers",
            description: "looking for two local openers for a sold-out indie bill.",
            isPaid: true,
            genres: [Genre.indiePop.rawValue, Genre.rock.rawValue],
            venueId: "venue-camel"
        ),
        Opportunity(
            id: "op-late-night-house",
            userId: "venue-canal",
            location: venues[3].location ?? .rva,
            timestamp: referenceDate,
            startTime: referenceDate.addingTimeInterval(9 * 24 * 60 * 60),
            endTime: referenceDate.addingTimeInterval(9 * 24 * 60 * 60 + 4 * 60 * 60),
            title: "late night house residency",
            description: "monthly residency, 11pm–3am.",
            isPaid: true,
            genres: [Genre.dance.rawValue, Genre.electronic.rawValue],
            venueId: "venue-canal"
        ),
        Opportunity(
            id: "op-jazz-brunch",
            userId: "venue-vagabond",
            location: venues[9].location ?? .rva,
            timestamp: referenceDate,
            startTime: referenceDate.addingTimeInterval(12 * 24 * 60 * 60),
            endTime: referenceDate.addingTimeInterval(12 * 24 * 60 * 60 + 2 * 60 * 60),
            title: "sunday jazz brunch",
            description: "trio or duo, acoustic.",
            isPaid: false,
            genres: [Genre.jazz.rawValue],
            venueId: "venue-vagabond"
        ),
        Opportunity(
            id: "op-open-decks",
            userId: "venue-broadberry",
            location: venues[2].location ?? .rva,
            timestamp: referenceDate,
            startTime: referenceDate.addingTimeInterval(7 * 24 * 60 * 60),
            endTime: referenceDate.addingTimeInterval(7 * 24 * 60 * 60 + 3 * 60 * 60),
            deadline: referenceDate.addingTimeInterval(4 * 24 * 60 * 60),
            title: "open decks thursday",
            description: "bring a usb. 45-minute sets, house and disco welcome. drink tickets for every dj.",
            isPaid: false,
            genres: [Genre.electronic.rawValue, Genre.dance.rawValue],
            venueId: "venue-broadberry"
        ),
        Opportunity(
            id: "op-patio-sessions",
            userId: "venue-hardywood",
            location: venues[5].location ?? .rva,
            timestamp: referenceDate,
            startTime: referenceDate.addingTimeInterval(14 * 24 * 60 * 60),
            endTime: referenceDate.addingTimeInterval(14 * 24 * 60 * 60 + 3 * 60 * 60),
            title: "patio sessions",
            description: "saturday afternoon acoustic sets on the brewery patio. folk, americana and funk-leaning bands.",
            isPaid: true,
            genres: [Genre.folk.rawValue, Genre.americana.rawValue, Genre.funk.rawValue],
            venueId: "venue-hardywood"
        ),
    ]

    private static let day: TimeInterval = 24 * 60 * 60
    private static let hour: TimeInterval = 60 * 60

    /// Richmond venues' `Location.placeId`s are `sample-<venue id>`; this one resolves in `MockPlacesRepository`.
    public static let washington = Location(placeId: "ChIJW-T2Wt7Gt4kRKl2I1CJFUsI", lat: 38.9072, lng: -77.0369)

    /// `performer`'s bookings: pending + upcoming + past + canceled, as requestee and as requester.
    public static let bookings: [Booking] = [
        Booking(
            id: "booking-1",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(3 * day),
            endTime: referenceDate.addingTimeInterval(3 * day + 2 * hour),
            timestamp: referenceDate,
            requesterId: "venue-camel",
            name: "camel sessions",
            rate: 25_000,
            genres: [Genre.dance.rawValue],
            location: venues[0].location
        ),
        Booking(
            id: "booking-2",
            requesteeId: performer.id,
            status: .pending,
            startTime: referenceDate.addingTimeInterval(10 * day + 23 * hour),
            endTime: referenceDate.addingTimeInterval(11 * day + 3 * hour),
            timestamp: referenceDate,
            requesterId: "venue-canal",
            name: "late night house",
            note: "headline slot after our resident. we have cdjs + a djm-900.",
            genres: [Genre.dance.rawValue, Genre.electronic.rawValue],
            location: venues[3].location
        ),
        Booking(
            id: "booking-3",
            requesteeId: "performer-mara",
            status: .pending,
            startTime: referenceDate.addingTimeInterval(14 * day + 19 * hour),
            endTime: referenceDate.addingTimeInterval(14 * day + 21 * hour),
            timestamp: referenceDate,
            requesterId: performer.id,
            name: "b2b at balliceaux",
            note: "would love a live vocal set over my closing hour.",
            location: venues[7].location
        ),
        Booking(
            id: "booking-4",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-20 * day),
            endTime: referenceDate.addingTimeInterval(-20 * day + 3 * hour),
            timestamp: referenceDate.addingTimeInterval(-40 * day),
            requesterId: "venue-broadberry",
            name: "broadberry disco night",
            genres: [Genre.funk.rawValue],
            location: venues[2].location
        ),
        Booking(
            id: "booking-5",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-45 * day),
            endTime: referenceDate.addingTimeInterval(-45 * day + 2 * hour),
            timestamp: referenceDate.addingTimeInterval(-60 * day),
            requesterId: "venue-national",
            name: "support slot",
            location: venues[1].location
        ),
        Booking(
            id: "booking-6",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-80 * day),
            endTime: referenceDate.addingTimeInterval(-80 * day + 4 * hour),
            timestamp: referenceDate.addingTimeInterval(-80 * day),
            verified: true,
            name: "hardywood block party",
            addedByUser: true,
            location: venues[5].location
        ),
        Booking(
            id: "booking-7",
            requesteeId: performer.id,
            status: .confirmed,
            startTime: referenceDate.addingTimeInterval(-120 * day),
            endTime: referenceDate.addingTimeInterval(-120 * day + 3 * hour),
            timestamp: referenceDate.addingTimeInterval(-120 * day),
            verified: true,
            name: "dc warehouse party",
            addedByUser: true,
            location: washington
        ),
        Booking(
            id: "booking-8",
            requesteeId: performer.id,
            status: .canceled,
            startTime: referenceDate.addingTimeInterval(-12 * day),
            endTime: referenceDate.addingTimeInterval(-12 * day + 2 * hour),
            timestamp: referenceDate.addingTimeInterval(-30 * day),
            requesterId: "venue-vagabond",
            name: "sunday brunch set",
            location: venues[9].location
        ),
    ]

    public static let services: [Service] = [
        Service(id: "service-dj-set", userId: performer.id, title: "dj set", description: "house + disco, bring-your-own-decks optional.", rate: 15_000, rateType: .hourly, count: 18),
        Service(id: "service-opener", userId: performer.id, title: "opening set", description: "60–90 minute warm-up before your headliner.", rate: 25_000, rateType: .fixed, count: 9),
        Service(id: "service-private", userId: performer.id, title: "private event", description: "weddings, launches and birthdays. sound system included.", rate: 80_000, rateType: .fixed, count: 4),
        Service(id: "service-mara-live", userId: "performer-mara", title: "live vocal set", description: "45 minutes of originals with a backing track.", rate: 30_000, rateType: .fixed, count: 12),
        Service(id: "service-mara-feature", userId: "performer-mara", title: "feature vocals", description: "top-line vocals over a dj set.", rate: 12_000, rateType: .hourly, count: 5),
    ]
}
