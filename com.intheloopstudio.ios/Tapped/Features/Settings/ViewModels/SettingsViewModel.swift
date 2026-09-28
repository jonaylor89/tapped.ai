import Foundation
import Observation
import TappedData
import TappedDomain
import UIKit

/// Port of `SettingsCubit` + `SettingsState` (payments / connect-bank intentionally dropped).
@Observable
@MainActor
final class SettingsViewModel {
    static let maxBioLength = 256

    /// Edited copy of the current user; the form binds straight to it.
    var draft: UserModel
    var username: String
    private(set) var placeName: String?
    private(set) var pickedImage: UIImage?
    private(set) var services: [Service] = []
    private(set) var isSaving = false
    private(set) var isDeleting = false
    var errorMessage: String?

    private var original: UserModel
    private var pickedImageData: Data?
    private let auth: any AuthRepository
    private let database: any DatabaseRepository
    private let places: any PlacesRepository
    private let storage: any StorageRepository
    private let analytics: any AnalyticsRepository

    init(dependencies: Dependencies, currentUser: UserModel) {
        original = currentUser
        draft = currentUser
        username = currentUser.username.username
        auth = dependencies.auth
        database = dependencies.database
        places = dependencies.places
        storage = dependencies.storage
        analytics = dependencies.analytics
    }

    var hasChanges: Bool { draft != original || Username(username) != original.username || pickedImageData != nil }

    var profilePictureURL: URL? { draft.profilePicture.flatMap(URL.init(string:)) }

    var bioCountLabel: String { "\(draft.bio.count)/\(Self.maxBioLength)" }

    /// Performer fields are edited through this so users without `performerInfo` get the Dart defaults.
    var performer: PerformerInfo {
        get { draft.performerInfo ?? PerformerInfo() }
        set { draft.performerInfo = newValue }
    }

    var isPerformer: Bool {
        get { draft.performerInfo != nil }
        set { draft.performerInfo = newValue ? (original.performerInfo ?? PerformerInfo()) : nil }
    }

    var selectedGenres: Set<Genre> {
        get { Set(performer.genres.compactMap(Genre.init(rawValue:))) }
        set { performer.genres = Genre.allCases.filter(newValue.contains).map(\.rawValue) }
    }

    var genresSummary: String {
        let genres = Genre.allCases.filter(selectedGenres.contains)
        return genres.isEmpty ? "none" : genres.map { $0.formattedName.lowercased() }.joined(separator: ", ")
    }

    /// `performerInfo.averageTicketPrice` is stored in cents.
    var ticketPriceDollars: Int? {
        get { performer.averageTicketPrice.map { $0 / 100 } }
        set { performer.averageTicketPrice = newValue.map { $0 * 100 } }
    }

    func load() async {
        async let services = try? database.getUserServices(draft.id)
        async let place: Void = loadPlaceName()
        self.services = await services ?? []
        await place
    }

    func setPickedImage(_ data: Data) {
        guard let image = UIImage(data: data), let jpeg = Self.compressedJPEG(image) else {
            errorMessage = "couldn't read that photo"
            return
        }
        pickedImage = image
        pickedImageData = jpeg
    }

    func selectPlace(_ place: PlaceData) {
        draft.location = Location(placeId: place.placeId, lat: place.lat, lng: place.lng)
        placeName = place.shortFormattedAddress ?? place.name
    }

    func clearLocation() {
        draft.location = nil
        placeName = nil
    }

    func searchPlaces(_ query: String) async -> [AutocompletePrediction] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return (try? await places.searchPlace(query)) ?? []
    }

    func place(for prediction: AutocompletePrediction) async -> PlaceData? {
        try? await places.getPlaceById(prediction.placeId)
    }

    func deleteService(_ service: Service) async {
        services.removeAll { $0.id == service.id }
        do {
            try await database.deleteService(draft.id, service.id)
        } catch {
            errorMessage = "couldn't delete service"
            services = (try? await database.getUserServices(draft.id)) ?? services
        }
    }

    /// Dart `saveProfile`. Returns the saved user on success.
    func save() async -> UserModel? {
        errorMessage = nil
        let username = Username(username)
        guard !username.username.isEmpty else {
            errorMessage = "username can't be empty"
            return nil
        }
        guard username.username.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else {
            errorMessage = "usernames can only contain letters, numbers, . and _"
            return nil
        }
        guard draft.bio.count <= Self.maxBioLength else {
            errorMessage = "bio must be \(Self.maxBioLength) characters or fewer"
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if username != original.username {
                guard try await database.checkUsernameAvailability(username.username, userId: draft.id) else {
                    errorMessage = "username already exists"
                    return nil
                }
            }
            var user = draft
            user.username = username
            user.artistName = user.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
            user.bio = user.bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pickedImageData {
                let url = try await storage.uploadProfilePicture(userId: user.id, imageData: pickedImageData)
                user.profilePicture = url.absoluteString
            }
            try await database.updateUserData(user)
            await analytics.track("update_profile")
            self.pickedImageData = nil
            draft = user
            original = user
            self.username = user.username.username
            return user
        } catch {
            errorMessage = "couldn't save your profile"
            return nil
        }
    }

    /// Dart `deleteUser` (after re-auth): deleting the auth user signs the session out.
    func deleteAccount() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteUser()
            await analytics.track("delete_account")
            return true
        } catch {
            errorMessage = "log in again, then retry deleting your account"
            return false
        }
    }

    private func loadPlaceName() async {
        guard let placeId = draft.location?.placeId, let place = try? await places.getPlaceById(placeId) else { return }
        placeName = place.shortFormattedAddress ?? place.name
    }

    /// Resizes to at most 1080px on the long edge and encodes as JPEG (Dart `compressImage`, quality 70).
    static func compressedJPEG(_ image: UIImage, maxDimension: CGFloat = 1080) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
