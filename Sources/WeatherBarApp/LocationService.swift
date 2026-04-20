import CoreLocation
import Foundation
import WeatherBarCore

@MainActor
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pendingRequests: [PendingLocationRequest] = []
    private var isRequestInFlight = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func currentLocation() async throws -> LocationFix {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequests.append(PendingLocationRequest(id: id, continuation: continuation))
                startLocationRequestIfNeeded()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelPendingRequest(id)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationStatus(status)
        }
    }

    private func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !pendingRequests.isEmpty else { return }
            isRequestInFlight = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(WeatherError.locationUnavailable("Location access is disabled for WeatherBar.")))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(WeatherError.locationUnavailable("Location authorization is unavailable.")))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.handleUpdatedLocations(locations)
        }
    }

    private func handleUpdatedLocations(_ locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherError.locationUnavailable("macOS did not return a location.")))
            return
        }

        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                let name = Self.bestName(from: placemarks?.first)
                self?.finish(.success(LocationFix(
                    coordinate: coordinate,
                    horizontalAccuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                    displayName: name,
                    resolvedAt: Date()
                )))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(.failure(error))
        }
    }

    private func startLocationRequestIfNeeded() {
        guard !pendingRequests.isEmpty, !isRequestInFlight else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            isRequestInFlight = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestInFlight = true
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(WeatherError.locationUnavailable("Location access is disabled for WeatherBar.")))
        @unknown default:
            finish(.failure(WeatherError.locationUnavailable("Location authorization is unavailable.")))
        }
    }

    private func cancelPendingRequest(_ id: UUID) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingRequests.remove(at: index)
        request.continuation.resume(throwing: CancellationError())
        if pendingRequests.isEmpty {
            geocoder.cancelGeocode()
            manager.stopUpdatingLocation()
            isRequestInFlight = false
        }
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        let requests = pendingRequests
        pendingRequests.removeAll()
        isRequestInFlight = false
        requests.forEach { $0.continuation.resume(with: result) }
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

    private struct PendingLocationRequest {
        let id: UUID
        let continuation: CheckedContinuation<LocationFix, Error>
    }
}
