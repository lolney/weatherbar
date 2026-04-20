import Foundation
import WeatherBarCore

enum LocationMode: String, CaseIterable, Identifiable {
    case current
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .current: return "Use Current Location"
        case .manual: return "Manual Location"
        }
    }
}

enum ProviderMode: String, CaseIterable, Identifiable {
    case nwsWithOpenMeteo
    case openMeteoOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nwsWithOpenMeteo: return "NWS + Open-Meteo Details"
        case .openMeteoOnly: return "Open-Meteo Only"
        }
    }
}

struct SavedLocation: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    var locationFix: LocationFix {
        LocationFix(
            coordinate: coordinate,
            horizontalAccuracyMeters: nil,
            displayName: name,
            resolvedAt: Date()
        )
    }
}

final class AppSettings {
    static let shared = AppSettings()
    static let currentLocationID = "current"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var locationMode: LocationMode {
        get { LocationMode(rawValue: defaults.string(forKey: Keys.locationMode) ?? "") ?? .current }
        set { defaults.set(newValue.rawValue, forKey: Keys.locationMode) }
    }

    var providerMode: ProviderMode {
        get { ProviderMode(rawValue: defaults.string(forKey: Keys.providerMode) ?? "") ?? .nwsWithOpenMeteo }
        set { defaults.set(newValue.rawValue, forKey: Keys.providerMode) }
    }

    var selectedLocationID: String {
        get {
            if let selected = defaults.string(forKey: Keys.selectedLocationID) {
                return selected
            }
            if locationMode == .manual, let first = savedLocations.first {
                return first.id
            }
            return Self.currentLocationID
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedLocationID)
            defaults.set(newValue == Self.currentLocationID ? LocationMode.current.rawValue : LocationMode.manual.rawValue, forKey: Keys.locationMode)
        }
    }

    var savedLocations: [SavedLocation] {
        get {
            guard let data = defaults.data(forKey: Keys.savedLocations),
                  let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
                return [manualSavedLocation]
            }
            return locations
        }
        set {
            let cleaned = newValue
                .map { location in
                    SavedLocation(
                        id: location.id.isEmpty ? UUID().uuidString : location.id,
                        name: location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Location" : location.name,
                        latitude: location.latitude,
                        longitude: location.longitude
                    )
                }
            if let data = try? JSONEncoder().encode(cleaned) {
                defaults.set(data, forKey: Keys.savedLocations)
            }
            if selectedLocationID != Self.currentLocationID,
               !cleaned.contains(where: { $0.id == selectedLocationID }) {
                selectedLocationID = Self.currentLocationID
            }
        }
    }

    var manualLocationName: String {
        get { defaults.string(forKey: Keys.manualLocationName) ?? "Cole Valley" }
        set { defaults.set(newValue, forKey: Keys.manualLocationName) }
    }

    var manualLatitude: Double {
        get { value(for: Keys.manualLatitude) ?? 37.7651 }
        set { defaults.set(newValue, forKey: Keys.manualLatitude) }
    }

    var manualLongitude: Double {
        get { value(for: Keys.manualLongitude) ?? -122.4497 }
        set { defaults.set(newValue, forKey: Keys.manualLongitude) }
    }

    var manualLocationFix: LocationFix {
        manualSavedLocation.locationFix
    }

    func location(named id: String) -> SavedLocation? {
        savedLocations.first { $0.id == id }
    }

    private var manualSavedLocation: SavedLocation {
        SavedLocation(
            id: "manual-location",
            name: manualLocationName,
            latitude: manualLatitude,
            longitude: manualLongitude
        )
    }

    private func value(for key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }

    private enum Keys {
        static let locationMode = "locationMode"
        static let providerMode = "providerMode"
        static let selectedLocationID = "selectedLocationID"
        static let savedLocations = "savedLocations"
        static let manualLocationName = "manualLocationName"
        static let manualLatitude = "manualLatitude"
        static let manualLongitude = "manualLongitude"
    }
}

final class SettingsLocationProvider: LocationProviding {
    private let settings: AppSettings
    private let currentProvider: LocationProviding

    init(settings: AppSettings = .shared, currentProvider: LocationProviding) {
        self.settings = settings
        self.currentProvider = currentProvider
    }

    func currentLocation() async throws -> LocationFix {
        if settings.selectedLocationID == AppSettings.currentLocationID {
            return try await currentProvider.currentLocation()
        }
        return settings.location(named: settings.selectedLocationID)?.locationFix ?? settings.manualLocationFix
    }
}
