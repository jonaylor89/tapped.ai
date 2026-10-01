import Foundation
import Observation
import TappedData

/// Port of `LocationFormCubit`: debounced Google Places autocomplete, then place details on selection.
@Observable
@MainActor
final class LocationFormViewModel {
    let initialPlace: PlaceData?
    var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    private(set) var predictions: [AutocompletePrediction] = []
    private(set) var isSearching = false
    private(set) var resolvingPlaceId: String?
    private(set) var failed = false

    private let places: any PlacesRepository
    private let debounce: Duration
    private let placesSessionToken = UUID().uuidString
    private var searchTask: Task<Void, Never>?

    init(dependencies: Dependencies, initialPlace: PlaceData?, debounce: Duration = SearchViewModel.debounce) {
        places = dependencies.places
        self.initialPlace = initialPlace
        self.debounce = debounce
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            predictions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.runSearch(term)
        }
    }

    func waitForSearch() async {
        await searchTask?.value
    }

    func resolve(_ prediction: AutocompletePrediction) async -> PlaceData? {
        resolvingPlaceId = prediction.placeId
        defer { resolvingPlaceId = nil }
        do {
            return try await places.getPlaceById(prediction.placeId, sessionToken: placesSessionToken)
        } catch {
            failed = true
            return nil
        }
    }

    private func runSearch(_ term: String) async {
        do {
            let results = try await places.searchPlace(term, sessionToken: placesSessionToken)
            guard !Task.isCancelled else { return }
            predictions = results
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            predictions = []
            failed = true
        }
        isSearching = false
    }
}
