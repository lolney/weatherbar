import Foundation
import WeatherBarCore

enum LocationMode: String {
    case current
    case manual
}

enum ProviderMode: String {
    case nwsWithOpenMeteo
    case openMeteoOnly
}

final class AppSettings {
    static let shared = AppSettings()

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
        LocationFix(
            coordinate: Coordinate(latitude: manualLatitude, longitude: manualLongitude),
            horizontalAccuracyMeters: nil,
            displayName: manualLocationName,
            resolvedAt: Date()
        )
    }

    private func value(for key: String) -> Double? {
        defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
    }

    private enum Keys {
        static let locationMode = "locationMode"
        static let providerMode = "providerMode"
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
        switch settings.locationMode {
        case .current:
            return try await currentProvider.currentLocation()
        case .manual:
            return settings.manualLocationFix
        }
    }
}
