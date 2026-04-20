import CoreLocation
import Foundation
import WeatherBarCore

final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var continuation: CheckedContinuation<LocationFix, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func currentLocation() async throws -> LocationFix {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                finish(.failure(WeatherError.locationUnavailable("Location access is disabled for WeatherBar.")))
            @unknown default:
                finish(.failure(WeatherError.locationUnavailable("Location authorization is unavailable.")))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(WeatherError.locationUnavailable("Location access is disabled for WeatherBar.")))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(WeatherError.locationUnavailable("Location authorization is unavailable.")))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherError.locationUnavailable("macOS did not return a location.")))
            return
        }

        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name = Self.bestName(from: placemarks?.first)
            self?.finish(.success(LocationFix(
                coordinate: coordinate,
                horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                displayName: name,
                resolvedAt: Date()
            )))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private static func bestName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            return subLocality
        }
        if let locality = placemark.locality, !locality.isEmpty {
            return locality
        }
        if let name = placemark.name, !name.isEmpty {
            return name
        }
        return nil
    }
}
