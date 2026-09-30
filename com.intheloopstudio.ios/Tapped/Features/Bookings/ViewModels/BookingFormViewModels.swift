import Foundation
import Observation
import TappedData
import TappedDomain
import TappedUI

extension PlaceData {
    var location: Location { Location(placeId: placeId, lat: lat, lng: lng) }
    var displayAddress: String { shortFormattedAddress ?? name }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfBlank: String? { trimmed.isEmpty ? nil : trimmed }
}

enum BookingFormDefaults {
    /// `dayOffset` days from today at `hour`:00 local time.
    static func start(now: Date, dayOffset: Int, hour: Int = 20) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}

/// `lib/ui/create_booking/create_booking_cubit.dart` without the deprecated Stripe/payment step.
@Observable
@MainActor
final class CreateBookingViewModel {
    private(set) var isSubmitting = false
    var errorMessage: String?
    var place: PlaceData?

    let currentUser: UserModel
    let now: () -> Date
    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository
    private let makeId: () -> String

    private func submit<T>(failure: String, _ operation: () async throws -> T) async -> T? {
        guard !isSubmitting else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            return try await operation()
        } catch {
            errorMessage = failure
            return nil
        }
    }

    let requesteeId: String
    var name = ""
    var note = ""
    var start: Date {
        didSet {
            if end <= start { end = start.addingTimeInterval(duration > 0 ? duration : Self.defaultDuration) }
        }
    }
    var end: Date
    var selectedServiceId: String?
    private(set) var requestee: UserModel?
    private(set) var services: [Service] = []

    static let defaultDuration: TimeInterval = 2 * 60 * 60

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        requesteeId: String,
        service: Service?,
        now: @escaping () -> Date = { .now },
        makeId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.requesteeId = requesteeId
        let start = BookingFormDefaults.start(now: now(), dayOffset: 1)
        self.start = start
        end = start.addingTimeInterval(Self.defaultDuration)
        selectedServiceId = service?.id
        if let service { services = [service] }
        database = dependencies.database
        analytics = dependencies.analytics
        self.currentUser = currentUser
        self.now = now
        self.makeId = makeId
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var selectedService: Service? { services.first { $0.id == selectedServiceId } }

    var validationMessage: String? {
        if requesteeId == currentUser.id { return "you can't book yourself" }
        if name.trimmed.isEmpty { return "add an event name" }
        if place == nil { return "choose a location" }
        if start < now() { return "the start time has already passed" }
        if end <= start { return "the end time must be after the start" }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    func load() async {
        let database = database
        let requesteeId = requesteeId
        async let requestee = try? await database.getUserById(requesteeId)
        async let services = try? await database.getUserServices(requesteeId)
        self.requestee = await requestee
        if let loaded = await services, !loaded.isEmpty { self.services = loaded }
        if let selectedServiceId, !self.services.contains(where: { $0.id == selectedServiceId }) { self.selectedServiceId = nil }
    }

    func submit() async -> Booking? {
        guard canSubmit, let place else { return nil }
        let service = selectedService
        let booking = Booking(
            id: makeId(),
            requesteeId: requesteeId,
            status: .pending,
            startTime: start,
            endTime: end,
            timestamp: now(),
            requesterId: currentUser.id,
            name: name.trimmed,
            note: note.trimmed,
            rate: service?.performerCost(start: start, end: end) ?? 0,
            serviceId: service?.id,
            genres: requestee?.performerInfo?.genres ?? [],
            location: place.location
        )
        return await submit(failure: "couldn't send the booking request") {
            try await database.createBooking(booking)
            await analytics.track("booking_requested", properties: ["booking_id": .string(booking.id), "has_service": .bool(service != nil)])
            return booking
        }
    }
}

/// `lib/ui/add_past_booking/add_past_booking_cubit.dart`. Flier upload and amount paid are not ported.
@Observable
@MainActor
final class AddPastBookingViewModel {
    private(set) var isSubmitting = false
    var errorMessage: String?
    var place: PlaceData?
    /// The current user with the `performerInfo.category` re-classified after the booking was added.
    private(set) var updatedUser: UserModel?

    let currentUser: UserModel
    let now: () -> Date
    private let database: any DatabaseRepository
    private let analytics: any AnalyticsRepository
    private let makeId: () -> String

    private func submit<T>(failure: String, _ operation: () async throws -> T) async -> T? {
        guard !isSubmitting else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            return try await operation()
        } catch {
            errorMessage = failure
            return nil
        }
    }

    var name = ""
    var note = ""
    var start: Date
    var duration: TimeInterval = 3 * 60 * 60

    static let durations: [TimeInterval] = [1, 2, 3, 4, 5, 6, 8].map { $0 * 60 * 60 }

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        now: @escaping () -> Date = { .now },
        makeId: @escaping () -> String = { UUID().uuidString }
    ) {
        start = BookingFormDefaults.start(now: now(), dayOffset: -7)
        database = dependencies.database
        analytics = dependencies.analytics
        self.currentUser = currentUser
        self.now = now
        self.makeId = makeId
    }

    var end: Date { start.addingTimeInterval(duration) }

    var validationMessage: String? {
        if name.trimmed.isEmpty { return "add an event name" }
        if place == nil { return "choose a location" }
        if start > now() { return "past bookings must start in the past" }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    func submit() async -> Booking? {
        guard canSubmit, let place else { return nil }
        let booking = Booking(
            id: makeId(),
            requesteeId: currentUser.id,
            status: .confirmed,
            startTime: start,
            endTime: end,
            timestamp: now(),
            verified: true,
            name: name.trimmed,
            note: note.trimmed,
            addedByUser: true,
            genres: currentUser.performerInfo?.genres ?? [],
            location: place.location
        )
        let created = await submit(failure: "couldn't add the booking") {
            try await database.createBooking(booking)
            await analytics.track("past_booking_added", properties: ["booking_id": .string(booking.id)])
            return booking
        }
        if created != nil { await reclassify() }
        return created
    }

    /// Dart `classifyPerformer` + `UpdateOnboardedUser`; best-effort since the booking already exists.
    private func reclassify() async {
        guard let category = try? await database.classifyPerformer(currentUser.id) else { return }
        var user = (try? await database.getUserById(currentUser.id)) ?? currentUser
        user.performerInfo?.category = category
        guard (try? await database.updateUserData(user)) != nil else { return }
        updatedUser = user
    }
}

/// `lib/ui/request_to_perform/request_to_perform_view.dart`: one Tapped API email thread per venue.
@Observable
@MainActor
final class RequestToPerformViewModel {
    var venues: [UserModel]
    var collaborators: [UserModel]
    var note = ""
    private(set) var isSubmitting = false
    var errorMessage: String?

    let currentUser: UserModel
    private let outreach: any VenueOutreachRepository
    private let analytics: any AnalyticsRepository
    private let makeId: () -> String

    init(
        dependencies: Dependencies,
        currentUser: UserModel,
        venues: [UserModel],
        collaborators: [UserModel],
        makeId: @escaping () -> String = { UUID().uuidString }
    ) {
        outreach = dependencies.venueOutreach
        analytics = dependencies.analytics
        self.currentUser = currentUser
        self.venues = venues
        self.collaborators = collaborators
        self.makeId = makeId
    }

    var validationMessage: String? {
        if venues.isEmpty { return "add at least one venue" }
        if note.trimmed.isEmpty { return "write a message to the venue" }
        return nil
    }

    var canSubmit: Bool { validationMessage == nil && !isSubmitting }

    var subject: String { "Performance inquiry from \(currentUser.displayName)" }

    var textBody: String {
        let names = collaborators.map(\.displayName).joined(separator: ", ")
        return names.isEmpty ? note.trimmed : "\(note.trimmed)\n\nCollaborators: \(names)"
    }

    func submit() async -> [UserModel]? {
        guard canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let requestId = makeId()
        let venues = venues
        let outreach = outreach
        let subject = subject
        let textBody = textBody
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for venue in venues {
                    group.addTask {
                        try await outreach.createVenueEmailThread(id: "\(requestId):\(venue.id)", venueId: venue.id, subject: subject, textBody: textBody)
                    }
                }
                try await group.waitForAll()
            }
            await analytics.track("request_to_perform", properties: ["venues": .int(venues.count), "collaborators": .int(collaborators.count)])
            return venues
        } catch {
            errorMessage = ErrorCopy.action("send your pitch")
            return nil
        }
    }
}

/// Google Places autocomplete for the booking forms' location row.
@Observable
@MainActor
final class LocationSearchViewModel {
    var query = ""
    private(set) var results: [AutocompletePrediction] = []
    private(set) var isSearching = false
    private(set) var isResolving = false
    var errorMessage: String?

    private let places: any PlacesRepository

    init(dependencies: Dependencies) {
        places = dependencies.places
    }

    func search() async {
        let query = query.trimmed
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(250))
            results = try await places.searchPlace(query)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = ErrorCopy.action("search places")
        }
    }

    func resolve(_ prediction: AutocompletePrediction) async -> PlaceData? {
        isResolving = true
        defer { isResolving = false }
        do {
            return try await places.getPlaceById(prediction.placeId)
        } catch {
            errorMessage = ErrorCopy.load("that place")
            return nil
        }
    }
}

/// `lib/ui/booking_history/booking_history_cubit.dart`: confirmed gigs the user played, on a map.
@Observable
@MainActor
final class BookingHistoryViewModel {
    let user: UserModel
    private(set) var bookings: [Booking] = []
    private(set) var users: [String: UserModel] = [:]
    private(set) var isLoading = true
    var selectedBookingId: String?

    static let limit = 250

    private let database: any DatabaseRepository
    private let now: () -> Date

    init(dependencies: Dependencies, user: UserModel, now: @escaping () -> Date = { .now }) {
        database = dependencies.database
        self.user = user
        self.now = now
    }

    var mappedBookings: [Booking] { bookings.filter { $0.location != nil } }
    var selectedBooking: Booking? { bookings.first { $0.id == selectedBookingId } }

    var summary: String {
        let venues = Set(bookings.compactMap(\.requesterId)).count
        let gigs = bookings.count == 1 ? "1 gig" : "\(bookings.count) gigs"
        return venues == 0 ? gigs : "\(gigs) · \(venues) \(venues == 1 ? "venue" : "venues")"
    }

    func load() async {
        defer { isLoading = false }
        let now = now()
        let all = (try? await database.getBookingsByRequestee(user.id, limit: Self.limit, lastBookingRequestId: nil, status: .confirmed)) ?? []
        bookings = all.filter { $0.startTime <= now }.sorted { $0.startTime > $1.startTime }
        let ids = Array(Set(bookings.compactMap(\.requesterId)).subtracting(users.keys))
        let database = database
        for user in (try? await ids.concurrentUsers({ try await database.getUserById($0) })) ?? [] {
            users[user.id] = user
        }
    }

    func requester(for booking: Booking) -> UserModel? { booking.requesterId.flatMap { users[$0] } }
}
