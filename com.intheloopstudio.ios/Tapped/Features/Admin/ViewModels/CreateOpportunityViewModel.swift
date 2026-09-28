import Foundation
import Observation
import TappedData
import TappedDomain
import UIKit

/// `lib/ui/admin/create_opportunity_cubit.dart`.
@Observable
@MainActor
final class CreateOpportunityViewModel {
    enum ValidationError: Error, Equatable {
        case missingTitle
        case missingDescription
        case missingLocation

        var message: String {
            switch self {
            case .missingTitle: "missing title"
            case .missingDescription: "missing description"
            case .missingLocation: "missing location"
            }
        }
    }

    static let maxDescriptionLength = 512

    var title = ""
    var description = ""
    var isPaid = false
    var startTime: Date {
        didSet {
            // Keep the duration when the start moves, like `updateStartTime`.
            endTime = startTime.addingTimeInterval(duration)
        }
    }

    var endTime: Date
    private(set) var venue: UserModel?
    private(set) var place: PlaceData?
    private(set) var flierImage: UIImage?
    private(set) var isSubmitting = false
    var errorMessage: String?
    private(set) var created: Opportunity?

    var venueQuery = ""
    private(set) var venueResults: [UserModel] = []
    var placeQuery = ""
    private(set) var placeResults: [AutocompletePrediction] = []

    private let currentUserId: String
    private let dependencies: Dependencies
    private var duration: TimeInterval

    init(dependencies: Dependencies, currentUserId: String, now: Date = .now) {
        self.dependencies = dependencies
        self.currentUserId = currentUserId
        let start = Calendar.current.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
        startTime = start
        duration = 3 * 60 * 60
        endTime = start.addingTimeInterval(3 * 60 * 60)
    }

    var location: Location? {
        if let place { return Location(placeId: place.placeId, lat: place.lat, lng: place.lng) }
        return venue?.location
    }

    var locationSummary: String? {
        place?.shortFormattedAddress ?? place?.name
    }

    var canSubmit: Bool { !isSubmitting && endTime > startTime }

    func endTimeChanged(_ newValue: Date) {
        endTime = newValue
        duration = max(newValue.timeIntervalSince(startTime), 0)
    }

    // MARK: - flier

    func setFlier(data: Data?) {
        flierImage = data.flatMap(UIImage.init(data:))
    }

    func removeFlier() { flierImage = nil }

    // MARK: - where

    func searchVenues() async {
        let query = venueQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { venueResults = []; return }
        venueResults = (try? await dependencies.search.queryUsers(query, filters: .venues())) ?? []
    }

    func selectVenue(_ venue: UserModel?) {
        self.venue = venue
        venueQuery = ""
        venueResults = []
    }

    func searchPlaces() async {
        let query = placeQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { placeResults = []; return }
        placeResults = (try? await dependencies.places.searchPlace(query)) ?? []
    }

    func selectPlace(_ prediction: AutocompletePrediction) async {
        place = try? await dependencies.places.getPlaceById(prediction.placeId)
        placeQuery = ""
        placeResults = []
    }

    func clearPlace() { place = nil }

    // MARK: - submit

    func validate() throws(ValidationError) -> Location {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw .missingTitle }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw .missingDescription }
        guard let location else { throw .missingLocation }
        return location
    }

    @discardableResult
    func submit() async -> Opportunity? {
        guard !isSubmitting else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let location = try validate()
            let id = UUID().uuidString.lowercased()
            var flierUrl: String?
            if let jpeg = flierImage?.jpegData(compressionQuality: 0.8) {
                flierUrl = try await dependencies.storage.uploadOpportunityFlier(opportunityId: id, jpegData: jpeg).absoluteString
            }
            let opportunity = Opportunity(
                id: id,
                userId: currentUserId,
                location: location,
                timestamp: .now,
                startTime: startTime,
                endTime: endTime,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                flierUrl: flierUrl,
                isPaid: isPaid,
                genres: venue?.venueInfo?.genres ?? [],
                venueId: venue?.id
            )
            try await dependencies.database.createOpportunity(opportunity)
            try await dependencies.database.copyOpportunityToFeeds(opportunity)
            await dependencies.analytics.track("opportunity_created", properties: ["opportunity_id": .string(id)])
            created = opportunity
            return opportunity
        } catch let error as ValidationError {
            errorMessage = error.message
        } catch {
            FirebaseBootstrap.record(error: error)
            errorMessage = "error creating opportunity"
        }
        return nil
    }
}
