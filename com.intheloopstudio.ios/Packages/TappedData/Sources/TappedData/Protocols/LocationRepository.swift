import Foundation

/// The device's current position. Used for one-tap "current city" after a `LocationButton` grant.
public protocol LocationRepository: Sendable {
    func currentCoordinate() async throws -> GeoCoordinate
}

public struct GeoCoordinate: Sendable, Hashable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

public enum LocationError: Error, Equatable, Sendable {
    case denied
    case unavailable
}
