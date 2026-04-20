import MapKit
import SwiftUI

struct LocationMapPicker: NSViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinate: $coordinate)
    }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.showsCompass = true
        mapView.showsScale = true

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didClickMap(_:)))
        mapView.addGestureRecognizer(click)
        context.coordinator.mapView = mapView
        context.coordinator.updateAnnotation(on: mapView, coordinate: coordinate, recenter: true)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.coordinate = $coordinate
        context.coordinator.updateAnnotation(on: mapView, coordinate: coordinate, recenter: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var coordinate: Binding<CLLocationCoordinate2D>
        weak var mapView: MKMapView?
        private let annotation = MKPointAnnotation()
        private var lastCenteredCoordinate: CLLocationCoordinate2D?

        init(coordinate: Binding<CLLocationCoordinate2D>) {
            self.coordinate = coordinate
        }

        @objc func didClickMap(_ recognizer: NSClickGestureRecognizer) {
            guard let mapView else { return }
            let point = recognizer.location(in: mapView)
            coordinate.wrappedValue = mapView.convert(point, toCoordinateFrom: mapView)
        }

        func updateAnnotation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D, recenter: Bool) {
            annotation.coordinate = coordinate
            if annotation.title == nil {
                annotation.title = "Selected Location"
                mapView.addAnnotation(annotation)
            }

            if recenter || shouldRecenter(to: coordinate) {
                let region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 4_000,
                    longitudinalMeters: 4_000
                )
                mapView.setRegion(region, animated: false)
                lastCenteredCoordinate = coordinate
            }
        }

        private func shouldRecenter(to coordinate: CLLocationCoordinate2D) -> Bool {
            guard let lastCenteredCoordinate else { return true }
            return abs(lastCenteredCoordinate.latitude - coordinate.latitude) > 0.01
                || abs(lastCenteredCoordinate.longitude - coordinate.longitude) > 0.01
        }
    }
}
