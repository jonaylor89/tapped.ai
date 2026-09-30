import Foundation
import Observation
import TappedData
import TappedDomain

/// `lib/ui/bookings/bookings_cubit.dart` + `user_bookings_feed.dart`: the user's bookings as requestee
/// and requester, bucketed into pending / upcoming / past.
@Observable
@MainActor
final class BookingsViewModel {
    enum Segment: String, CaseIterable, Hashable {
        case pending, upcoming, past
    }

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    static let pageSize = 100

    let userId: String
    var segment: Segment = .upcoming
    private(set) var bookings: [Booking] = []
    private(set) var users: [String: UserModel] = [:]
    private(set) var state: LoadState = .loading

    private let database: any DatabaseRepository
    private let now: () -> Date
    private var didPickInitialSegment = false

    init(dependencies: Dependencies, userId: String, now: @escaping () -> Date = { .now }) {
        database = dependencies.database
        self.userId = userId
        self.now = now
    }

    func load() async {
        if bookings.isEmpty { state = .loading }
        do {
            async let asRequestee = database.getBookingsByRequestee(userId, limit: Self.pageSize, lastBookingRequestId: nil, status: nil)
            async let asRequester = database.getBookingsByRequester(userId, limit: Self.pageSize, lastBookingRequestId: nil, status: nil)
            let all = try await asRequestee + asRequester
            var seen = Set<String>()
            bookings = all.filter { seen.insert($0.id).inserted }.sorted { $0.startTime < $1.startTime }
            state = .loaded
            if !didPickInitialSegment {
                didPickInitialSegment = true
                segment = bookings(in: .pending).isEmpty ? .upcoming : .pending
            }
            await loadCounterparts()
        } catch {
            if bookings.isEmpty { state = .failed("couldn't load your bookings") }
        }
    }

    func bookings(in segment: Segment) -> [Booking] {
        let now = now()
        switch segment {
        case .pending:
            return bookings.filter { $0.isPending && !$0.isExpired(now: now) }
        case .upcoming:
            return bookings.filter { $0.isConfirmed && $0.startTime > now }
        case .past:
            return bookings
                .filter { ($0.isConfirmed && $0.startTime <= now) || $0.isCanceled || ($0.isPending && $0.isExpired(now: now)) }
                .sorted { $0.startTime > $1.startTime }
        }
    }

    var visibleBookings: [Booking] { bookings(in: segment) }

    func counterpart(for booking: Booking) -> UserModel? {
        booking.counterpartId(for: userId).flatMap { users[$0] }
    }

    var emptyState: (title: String, message: String, systemImage: String) {
        switch segment {
        case .pending: ("no pending requests", "booking requests you send or receive show up here", "tray")
        case .upcoming: ("no upcoming gigs", "confirmed bookings show up here", "calendar")
        case .past: ("no past bookings", "add gigs you've already played to build your history", "clock.arrow.circlepath")
        }
    }

    private func loadCounterparts() async {
        let ids = Set(bookings.compactMap { $0.counterpartId(for: userId) }).subtracting(users.keys)
        let database = database
        let fetched = (try? await Array(ids).concurrentUsers { try await database.getUserById($0) }) ?? []
        for user in fetched { users[user.id] = user }
    }
}

extension Array where Element == String {
    /// Fetches users concurrently, dropping missing ids.
    func concurrentUsers(_ fetch: @escaping @Sendable (String) async throws -> UserModel?) async throws -> [UserModel] {
        try await withThrowingTaskGroup(of: UserModel?.self) { group in
            for id in self { group.addTask { try? await fetch(id) } }
            var users: [UserModel] = []
            for try await user in group { if let user { users.append(user) } }
            return users
        }
    }
}
