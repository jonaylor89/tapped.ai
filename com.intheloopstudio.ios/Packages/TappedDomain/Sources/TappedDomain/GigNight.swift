import Foundation

/// A confirmed booking the performer plays, as shown by the "Gig Night" Live Activity and the "Next gig" widget.
public struct GigNight: Codable, Sendable, Hashable, Identifiable {
    public var bookingId: String
    public var venueName: String
    public var latitude: Double?
    public var longitude: Double?
    public var startTime: Date
    public var endTime: Date

    public var id: String { bookingId }

    /// How long after the set the review prompt stays up before the activity ends on its own.
    public static let reviewWindow: TimeInterval = 12 * 60 * 60

    public init(bookingId: String, venueName: String, latitude: Double? = nil, longitude: Double? = nil, startTime: Date, endTime: Date) {
        self.bookingId = bookingId
        self.venueName = venueName
        self.latitude = latitude
        self.longitude = longitude
        self.startTime = startTime
        self.endTime = endTime
    }

    /// `nil` unless the booking is confirmed; the venue name comes from the booker's profile when known.
    public init?(booking: Booking, venueName: String?) {
        guard booking.isConfirmed else { return nil }
        let name = [venueName, booking.name].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        self.init(
            bookingId: booking.id,
            venueName: name ?? "your gig",
            latitude: booking.location?.lat,
            longitude: booking.location?.lng,
            startTime: booking.startTime,
            endTime: booking.endTime
        )
    }

    public var dismissalDate: Date { endTime.addingTimeInterval(Self.reviewWindow) }

    public func phase(at now: Date) -> GigNightPhase {
        if now < startTime { return .upcoming }
        if now < endTime { return .onStage }
        if now < dismissalDate { return .review }
        return .over
    }

    /// When the content for `phase` goes out of date (ActivityKit `staleDate`).
    public func staleDate(for phase: GigNightPhase) -> Date? {
        switch phase {
        case .upcoming: startTime
        case .onStage: endTime
        case .review: dismissalDate
        case .over: nil
        }
    }

    /// Gig night runs on the day of the set (and through its review window if the set crosses midnight).
    public func isGigNight(at now: Date, calendar: Calendar = .current) -> Bool {
        phase(at: now) != .over && (calendar.isDate(startTime, inSameDayAs: now) || startTime <= now)
    }

    /// `https://maps.apple.com/?ll=…&q=…`, `nil` without venue coordinates.
    public var directionsURL: URL? {
        guard let latitude, let longitude else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: venueName),
        ]
        return components?.url
    }

    /// Universal link the app already routes to the booking detail (and its review flow).
    public var bookingURL: URL {
        URL(string: "https://app.tapped.ai/booking/\(bookingId)") ?? URL(filePath: "/")
    }
}

public enum GigNightPhase: String, Codable, Sendable, Hashable, CaseIterable {
    case upcoming
    case onStage
    case review
    case over
}

/// Reconciles running Gig Night Live Activities with the performer's confirmed bookings.
public enum GigNightSync {
    public enum Action: Equatable, Sendable {
        case start(GigNight, GigNightPhase)
        case update(GigNight, GigNightPhase)
        case end(bookingId: String)
    }

    public static func actions(
        gigs: [GigNight],
        running: [String: GigNightPhase],
        dismissed: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) -> [Action] {
        let tonight = gigs.filter { $0.isGigNight(at: now, calendar: calendar) && !dismissed.contains($0.bookingId) }
        let tonightIds = Set(tonight.map(\.bookingId))
        var actions: [Action] = running.keys.sorted().filter { !tonightIds.contains($0) }.map { .end(bookingId: $0) }
        for gig in tonight.sorted(by: { $0.startTime < $1.startTime }) {
            let phase = gig.phase(at: now)
            switch running[gig.bookingId] {
            case nil: actions.append(.start(gig, phase))
            case phase: break
            default: actions.append(.update(gig, phase))
            }
        }
        return actions
    }
}
