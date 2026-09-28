import Foundation

/// `com.intheloopstudio/lib/domains/models/location.dart`
public struct Location: Codable, Sendable, Hashable, Identifiable {
    public var placeId: String
    public var lat: Double
    public var lng: Double

    public var id: String { placeId }

    public init(placeId: String, lat: Double, lng: Double) {
        self.placeId = placeId
        self.lat = lat
        self.lng = lng
    }

    public static let nyc = Location(placeId: "ChIJOwg_06VPwokRYv534QaPC8g", lat: 40.712775, lng: -74.005973)
    public static let rva = Location(placeId: "ChIJ7cmZVwkRsYkRxTxC4m0-2L8", lat: 37.5407246, lng: -77.4360481)
}
