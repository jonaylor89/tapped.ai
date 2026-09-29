import Foundation
import Observation
import TappedData
import TappedDomain
import TappedUI
import UIKit

extension UserModel {
    /// Dart `https://app.tapped.ai/u/${user.username}`.
    var profileURL: URL {
        URL(string: "https://app.tapped.ai/u/\(username.username)") ?? URL(string: "https://app.tapped.ai")!
    }
}

/// One labelled fact in the profile info card (`info_sliver.dart`).
struct ProfileInfoRow: Identifiable, Equatable {
    let title: String
    let value: String
    let systemImage: String
    var url: URL?

    var id: String { title }
}

/// A social account with an optional follower count (`social_media_icons.dart`).
struct ProfileSocial: Identifiable, Equatable {
    let name: String
    let handle: String
    let followers: Int
    let url: URL?
    let systemImage: String

    var id: String { name }
}

/// Port of `ProfileCubit` + `ProfileState`.
@Observable
@MainActor
final class ProfileViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let currentUser: UserModel
    let userId: String
    private(set) var user: UserModel?
    private(set) var phase: Phase = .loading
    private(set) var services: [Service] = []
    private(set) var latestBookings: [Booking] = []
    private(set) var bookingCounterparts: [String: UserModel] = [:]
    private(set) var latestReview: Review?
    private(set) var latestReviewer: UserModel?
    private(set) var placeName: String?
    private(set) var isBlocked = false
    private(set) var contactedVenuesCount = 0
    private(set) var isUploadingPhoto = false
    var toast: String?

    private let database: any DatabaseRepository
    private let places: any PlacesRepository
    private let analytics: any AnalyticsRepository
    private let storage: any StorageRepository

    init(dependencies: Dependencies, currentUser: UserModel, userId: String, user: UserModel? = nil) {
        self.currentUser = currentUser
        self.userId = userId
        self.user = user ?? (userId == currentUser.id ? currentUser : nil)
        database = dependencies.database
        places = dependencies.places
        analytics = dependencies.analytics
        storage = dependencies.storage
    }

    var isCurrentUser: Bool { currentUser.id == userId }

    var reviewCount: Int { (user?.performerInfo?.reviewCount ?? 0) + (user?.bookerInfo?.reviewCount ?? 0) }

    var bookingCount: Int { user?.performerInfo?.bookingCount ?? latestBookings.count }

    /// The "finish setting up" checklist (`TasksViewModel`) for the ring next to edit profile.
    var setupTasks: [SetupTask] {
        guard let user, isCurrentUser else { return [] }
        return TasksViewModel.tasks(for: user, hasBookings: !latestBookings.isEmpty, contactedVenuesCount: contactedVenuesCount)
    }

    var setupProgress: Double {
        let tasks = setupTasks
        return tasks.isEmpty ? 1 : Double(tasks.count(where: \.isCompleted)) / Double(tasks.count)
    }

    /// Own profile without a photo: show the inline "add a photo" prompt instead of a hero.
    var needsPhoto: Bool { isCurrentUser && (user?.profilePicture ?? "").isEmpty }

    /// Uploads through `StorageRepository` and saves the new URL on the user.
    func uploadPhoto(_ data: Data) async {
        guard var updated = user, isCurrentUser else { return }
        guard let jpeg = Self.jpeg(from: data) else {
            toast = "couldn't read that photo — try a different one"
            return
        }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let url = try await storage.uploadProfilePicture(userId: updated.id, imageData: jpeg)
            updated.profilePicture = url.absoluteString
            try await database.updateUserData(updated)
            user = updated
            toast = "photo added"
            await analytics.track("update_profile_picture")
        } catch {
            toast = ErrorCopy.action("upload your photo")
        }
    }

    private static func jpeg(from data: Data, maxDimension: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    /// Dart `showFollowers`.
    var showAudience: Bool { (user?.socialFollowing.audienceSize ?? 0) > 0 || isCurrentUser }

    var canMessage: Bool { !isCurrentUser && user?.unclaimed == false }

    /// Venues can be pitched directly; Dart only showed this for unclaimed venues.
    var canRequestToPerform: Bool { !isCurrentUser && (user?.isVenue == true || user?.unclaimed == true) }

    var canRequestToBook: Bool { !isCurrentUser && !services.isEmpty }

    var subtitle: String? {
        guard let user else { return nil }
        if let venue = user.venueInfo {
            let type = Self.spaced(venue.type.rawValue)
            return venue.capacity.map { "\(type) · \($0.formatted()) cap" } ?? type
        }
        return user.performerInfo.map { $0.category.formattedName } ?? user.occupations.first
    }

    var infoRows: [ProfileInfoRow] {
        guard let user else { return [] }
        var rows: [ProfileInfoRow] = []
        if let placeName { rows.append(.init(title: "location", value: placeName, systemImage: "mappin.and.ellipse")) }
        if let venue = user.venueInfo {
            if let capacity = venue.capacity { rows.append(.init(title: "capacity", value: capacity.formatted(), systemImage: "person.3.fill")) }
            if !venue.genres.isEmpty { rows.append(.init(title: "genres", value: Self.genreNames(venue.genres), systemImage: "music.note.list")) }
            if let email = venue.bookingEmail { rows.append(.init(title: "booking email", value: email, systemImage: "envelope.fill", url: URL(string: "mailto:\(email)"))) }
        }
        if let performer = user.performerInfo {
            if !performer.genres.isEmpty { rows.append(.init(title: "genres", value: Self.genreNames(performer.genres), systemImage: "music.note.list")) }
            if let price = performer.averageTicketPrice { rows.append(.init(title: "avg. ticket price", value: Self.currency(price), systemImage: "ticket.fill")) }
            if let attendance = performer.averageAttendance { rows.append(.init(title: "avg. attendance", value: attendance.formatted(), systemImage: "person.3.fill")) }
            rows.append(.init(title: "label", value: performer.label, systemImage: "opticaldisc.fill"))
            if let agency = performer.bookingAgency, !agency.isEmpty { rows.append(.init(title: "booking agency", value: agency, systemImage: "briefcase.fill")) }
            if let press = performer.pressKitUrl, let url = URL(string: press) { rows.append(.init(title: "press kit", value: "open", systemImage: "doc.richtext.fill", url: url)) }
            if let email = performer.bookingEmail, !email.isEmpty { rows.append(.init(title: "booking email", value: email, systemImage: "envelope.fill", url: URL(string: "mailto:\(email)"))) }
        }
        if let phone = user.phoneNumber, !phone.isEmpty { rows.append(.init(title: "phone", value: phone, systemImage: "phone.fill", url: URL(string: "tel:\(phone)"))) }
        if let website = user.website, let url = URL(string: website) { rows.append(.init(title: "website", value: url.host() ?? website, systemImage: "globe", url: url)) }
        return rows
    }

    var socials: [ProfileSocial] {
        guard let social = user?.socialFollowing else { return [] }
        func entry(_ name: String, _ handle: String?, _ followers: Int, _ base: String, _ symbol: String) -> ProfileSocial? {
            guard let handle, !handle.isEmpty else { return nil }
            return ProfileSocial(name: name, handle: handle, followers: followers, url: URL(string: base + handle), systemImage: symbol)
        }
        return [
            entry("instagram", social.instagramHandle, social.instagramFollowers, "https://instagram.com/", "camera.fill"),
            entry("tiktok", social.tiktokHandle, social.tiktokFollowers, "https://tiktok.com/@", "music.note"),
            entry("x", social.twitterHandle, social.twitterFollowers, "https://x.com/", "at"),
            entry("facebook", social.facebookHandle, social.facebookFollowers, "https://facebook.com/", "person.2.fill"),
            entry("youtube", social.youtubeHandle, 0, "https://youtube.com/@", "play.rectangle.fill"),
            entry("spotify", social.spotifyId, social.spotifyMonthlyListeners, "https://open.spotify.com/artist/", "waveform"),
            entry("soundcloud", social.soundcloudHandle, social.soundcloudFollowers, "https://soundcloud.com/", "cloud.fill"),
            entry("twitch", social.twitchHandle, social.twitchFollowers, "https://twitch.tv/", "tv.fill"),
            entry("audius", social.audiusHandle, social.audiusFollowers, "https://audius.co/", "headphones"),
        ].compactMap { $0 }
    }

    func load() async {
        if user == nil { phase = .loading }
        do {
            guard let fetched = try await database.getUserById(userId) else {
                if user == nil { phase = .failed("this profile doesn't exist") }
                return
            }
            user = fetched
        } catch {
            if user == nil {
                phase = .failed(ErrorCopy.load("this profile"))
                return
            }
        }
        phase = .loaded
        async let services: Void = loadServices()
        async let bookings: Void = loadLatestBookings()
        async let review: Void = loadLatestReview()
        async let blocked: Void = loadIsBlocked()
        async let place: Void = loadPlace()
        async let contacted: Void = loadContactedVenues()
        _ = await (services, bookings, review, blocked, place, contacted)
    }

    func block() async {
        isBlocked = true
        do {
            try await database.blockUser(currentUserId: currentUser.id, blockedUserId: userId)
            toast = "user blocked"
            await analytics.track("block_user", properties: ["blocked_user_id": .string(userId)])
        } catch {
            isBlocked = false
            toast = "couldn't block user"
        }
    }

    func unblock() async {
        isBlocked = false
        do {
            try await database.unblockUser(currentUserId: currentUser.id, blockedUserId: userId)
            toast = "user unblocked"
        } catch {
            isBlocked = true
            toast = "couldn't unblock user"
        }
    }

    func report() async {
        guard let user else { return }
        do {
            try await database.reportUser(reported: user, reporter: currentUser)
            toast = "user reported"
        } catch {
            toast = "couldn't report user"
        }
    }

    func counterpart(for booking: Booking) -> UserModel? {
        let otherId = booking.requesteeId == userId ? booking.requesterId : booking.requesteeId
        return otherId.flatMap { bookingCounterparts[$0] }
    }

    func counterpartName(for booking: Booking) -> String {
        counterpart(for: booking)?.displayName ?? booking.name ?? "booking"
    }

    // MARK: - loading

    private func loadServices() async {
        let services = (try? await database.getUserServices(userId)) ?? []
        self.services = services.sorted { $0.rate < $1.rate }
    }

    /// Dart `getTopBookings`: 5 confirmed as requestee + 5 as requester, newest first.
    private func loadLatestBookings() async {
        async let requestee = try? database.getBookingsByRequestee(userId, limit: 5, lastBookingRequestId: nil, status: .confirmed)
        async let requester = try? database.getBookingsByRequester(userId, limit: 5, lastBookingRequestId: nil, status: .confirmed)
        let bookings = ((await requestee ?? []) + (await requester ?? [])).sorted { $0.startTime > $1.startTime }
        latestBookings = bookings
        let ids = Set(bookings.flatMap { [$0.requesteeId, $0.requesterId].compactMap { $0 } }).subtracting([userId])
        for id in ids where bookingCounterparts[id] == nil {
            if let user = try? await database.getUserById(id) { bookingCounterparts[id] = user }
        }
    }

    /// Dart `getLatestReview`: newest of the latest performer + booker review.
    private func loadLatestReview() async {
        async let performer = try? database.getPerformerReviewsByPerformerId(userId, limit: 1, lastReviewId: nil)
        async let booker = try? database.getBookerReviewsByBookerId(userId, limit: 1, lastReviewId: nil)
        let candidates: [Review] = ((await performer ?? []).map(Review.performer)) + ((await booker ?? []).map(Review.booker))
        latestReview = candidates.max { $0.fields.timestamp < $1.fields.timestamp }
        guard let latestReview else { return }
        let reviewerId = latestReview.type == .performer ? latestReview.fields.bookerId : latestReview.fields.performerId
        latestReviewer = try? await database.getUserById(reviewerId)
    }

    private func loadContactedVenues() async {
        guard isCurrentUser else { return }
        contactedVenuesCount = (try? await database.getContactedVenues(userId))?.count ?? 0
    }

    private func loadIsBlocked() async {
        guard !isCurrentUser else { return }
        isBlocked = (try? await database.isBlocked(currentUserId: currentUser.id, blockedUserId: userId)) ?? false
    }

    private func loadPlace() async {
        guard let placeId = user?.location?.placeId else { return }
        if let place = try? await places.getPlaceById(placeId) {
            placeName = place.shortFormattedAddress ?? place.name
        }
    }

    static func genreNames(_ rawValues: [String]) -> String {
        rawValues.map { Genre(rawValue: $0)?.formattedName ?? $0 }.joined(separator: ", ")
    }

    static func currency(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// `concertHall` -> `concert hall`.
    static func spaced(_ camelCase: String) -> String {
        camelCase.reduce(into: "") { result, character in
            if character.isUppercase { result += " " }
            result += character.lowercased()
        }
    }

    static func compact(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))).lowercased()
    }
}
