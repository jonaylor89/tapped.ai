import CoreLocation
import Foundation

/// One-shot `CLLocationManager.requestLocation()`. Callers get authorization first, typically from a
/// `CoreLocationUI` `LocationButton` tap (a one-time grant without the permission alert).
public struct CoreLocationRepository: LocationRepository {
    public init() {}

    public func currentCoordinate() async throws -> GeoCoordinate {
        try await OneShotLocationRequest().run()
    }
}

/// Owns a `CLLocationManager` for the lifetime of a single request.
@MainActor
private final class OneShotLocationRequest: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<GeoCoordinate, any Error>?

    func run() async throws -> GeoCoordinate {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError.denied
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<GeoCoordinate, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        manager.delegate = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let result = GeoCoordinate(lat: coordinate.latitude, lng: coordinate.longitude)
        MainActor.assumeIsolated { finish(.success(result)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { finish(.failure(denied ? LocationError.denied : LocationError.unavailable)) }
    }
}
