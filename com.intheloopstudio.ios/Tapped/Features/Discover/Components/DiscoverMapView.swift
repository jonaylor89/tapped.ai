import MapKit
import SwiftUI
import TappedData
import TappedDomain
import TappedUI

struct DiscoverAnnotationItem: Identifiable, Hashable {
    enum Kind: String {
        case venue
        case gig
    }

    let id: String
    let kind: Kind
    let title: String
    let location: Location
}

/// `MKMapView` bridge. SwiftUI `Map` has no clustering, so this uses MapKit's built-in
/// `clusteringIdentifier` on marker views.
struct DiscoverMapView: UIViewRepresentable {
    let items: [DiscoverAnnotationItem]
    let initialCenter: Location
    let initialSpanDegrees: Double
    let cameraRequest: MapCameraRequest?
    let onRegionChange: (GeoBounds) -> Void
    let onSelect: (String) -> Void
    /// Receives the `MKMapView` so `DiscoverCompass` can track its heading.
    var link: MapViewLink?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsUserLocation = CLLocationManager().authorizationStatus.isAuthorized
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.markerID)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.setRegion(Self.region(initialCenter, span: initialSpanDegrees), animated: false)
        if let link { Task { @MainActor in link.mapView = map } }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onRegionChange = onRegionChange
        coordinator.onSelect = onSelect
        coordinator.sync(items, on: map)
        if let cameraRequest, cameraRequest.id != coordinator.lastCameraRequestID {
            coordinator.lastCameraRequestID = cameraRequest.id
            Self.apply(cameraRequest, to: map)
        }
    }

    static func region(_ location: Location, span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    static func apply(_ request: MapCameraRequest, to map: MKMapView) {
        switch request.kind {
        case let .center(location, span):
            map.setRegion(region(location, span: span), animated: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        static let markerID = "discover.marker"

        var onRegionChange: (GeoBounds) -> Void = { _ in }
        var onSelect: (String) -> Void = { _ in }
        var lastCameraRequestID: UUID?
        private var current: [String: Annotation] = [:]

        func sync(_ items: [DiscoverAnnotationItem], on map: MKMapView) {
            let incoming = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let removed = current.filter { incoming[$0.key] != $0.value.item }
            map.removeAnnotations(Array(removed.values))
            removed.keys.forEach { current[$0] = nil }
            let added = incoming.values.filter { current[$0.id] == nil }.map(Annotation.init)
            added.forEach { current[$0.item.id] = $0 }
            map.addAnnotations(added)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            onRegionChange(GeoBounds(
                swLatitude: region.center.latitude - region.span.latitudeDelta / 2,
                swLongitude: region.center.longitude - region.span.longitudeDelta / 2,
                neLatitude: region.center.latitude + region.span.latitudeDelta / 2,
                neLongitude: region.center.longitude + region.span.longitudeDelta / 2
            ))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier,
                    for: cluster
                ) as? MKMarkerAnnotationView
                view?.markerTintColor = UIColor(TappedColors.accent)
                return view
            }
            guard let annotation = annotation as? Annotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.markerID, for: annotation) as? MKMarkerAnnotationView
            view?.clusteringIdentifier = annotation.item.kind.rawValue
            view?.markerTintColor = UIColor(TappedColors.accent)
            view?.glyphImage = UIImage(systemName: annotation.item.kind == .venue ? "building.2.fill" : "music.mic")
            view?.titleVisibility = .adaptive
            view?.displayPriority = .defaultHigh
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
            } else if let annotation = annotation as? Annotation {
                onSelect(annotation.item.id)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }
    }

    final class Annotation: NSObject, MKAnnotation {
        let item: DiscoverAnnotationItem
        let coordinate: CLLocationCoordinate2D
        var title: String? { item.title }

        init(_ item: DiscoverAnnotationItem) {
            self.item = item
            coordinate = CLLocationCoordinate2D(latitude: item.location.lat, longitude: item.location.lng)
        }
    }
}

private extension CLAuthorizationStatus {
    var isAuthorized: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}

#Preview {
    DiscoverMapView(
        items: Samples.venues.compactMap { v in v.location.map { DiscoverAnnotationItem(id: v.id, kind: .venue, title: v.displayName, location: $0) } },
        initialCenter: .rva,
        initialSpanDegrees: 0.12,
        cameraRequest: nil,
        onRegionChange: { _ in },
        onSelect: { _ in }
    )
    .ignoresSafeArea()
}

/// Hands the UIKit map to sibling views (compass) without making it SwiftUI state of the map itself.
@Observable
@MainActor
final class MapViewLink {
    var mapView: MKMapView?
}

/// `MKCompassButton` bound to the Discover map; visible only while the map is rotated.
struct DiscoverCompass: UIViewRepresentable {
    let mapView: MKMapView

    func makeUIView(context: Context) -> MKCompassButton {
        let button = MKCompassButton(mapView: mapView)
        button.compassVisibility = .adaptive
        return button
    }

    func updateUIView(_ button: MKCompassButton, context: Context) {
        button.mapView = mapView
    }
}
