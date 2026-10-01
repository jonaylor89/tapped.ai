import Foundation

/// Process-local cache for billable Google Places responses.
///
/// Google Places content is intentionally not persisted: Google Maps Platform terms limit
/// content storage, while this cache still eliminates duplicate requests caused by SwiftUI
/// view recreation and repeated searches during a single app session.
actor GooglePlacesCache {
    private struct Entry<Value: Sendable>: Sendable {
        let value: Value
        let expiresAt: Date

        func isValid(at date: Date) -> Bool { expiresAt > date }
    }

    private var autocomplete = [String: Entry<[AutocompletePrediction]>]()
    private var places = [String: Entry<PlaceData?>]()
    private var photos = [String: Entry<URL?>]()
    private var reverseGeocodes = [String: Entry<String?>]()

    func autocomplete(for query: String) -> [AutocompletePrediction]? {
        value(for: query, in: &autocomplete)
    }

    func storeAutocomplete(_ predictions: [AutocompletePrediction], for query: String) {
        store(predictions, for: query, ttl: 5 * 60, in: &autocomplete)
    }

    // Optional values use a double optional: `.some(nil)` is a cached negative response.
    func place(for placeId: String) -> PlaceData?? {
        value(for: placeId, in: &places)
    }

    func storePlace(_ place: PlaceData?, for placeId: String) {
        store(place, for: placeId, ttl: 60 * 60, in: &places)
    }

    func photo(for key: String) -> URL?? {
        value(for: key, in: &photos)
    }

    func storePhoto(_ photo: URL?, for key: String) {
        // Photo URIs are short-lived. Do not cache a stale redirect for longer than 30 minutes.
        store(photo, for: key, ttl: 30 * 60, in: &photos)
    }

    func reverseGeocode(for key: String) -> String?? {
        value(for: key, in: &reverseGeocodes)
    }

    func storeReverseGeocode(_ placeId: String?, for key: String) {
        store(placeId, for: key, ttl: 60 * 60, in: &reverseGeocodes)
    }

    private func value<Value: Sendable>(for key: String, in cache: inout [String: Entry<Value>]) -> Value? {
        guard let entry = cache[key] else { return nil }
        guard entry.isValid(at: .now) else {
            cache.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    private func store<Value: Sendable>(
        _ value: Value,
        for key: String,
        ttl: TimeInterval,
        in cache: inout [String: Entry<Value>]
    ) {
        if cache.count >= 500 {
            cache = cache.filter { $0.value.isValid(at: .now) }
            if cache.count >= 500, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                cache.removeValue(forKey: oldest)
            }
        }
        cache[key] = Entry(value: value, expiresAt: .now.addingTimeInterval(ttl))
    }
}
