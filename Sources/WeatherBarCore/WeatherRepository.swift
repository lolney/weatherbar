import Foundation

public actor WeatherRepository {
    private let provider: WeatherProvider
    private let locationProvider: LocationProviding
    private let ttl: TimeInterval
    private let now: () -> Date
    private var cachedSnapshot: WeatherSnapshot?

    public init(
        provider: WeatherProvider,
        locationProvider: LocationProviding,
        ttl: TimeInterval = 10 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.locationProvider = locationProvider
        self.ttl = ttl
        self.now = now
    }

    public func refresh(force: Bool = false) async throws -> WeatherSnapshot {
        if !force, let cachedSnapshot, now().timeIntervalSince(cachedSnapshot.fetchedAt) < ttl {
            return cachedSnapshot
        }

        let location = try await locationProvider.currentLocation()
        let snapshot = try await provider.fetchWeather(for: location.coordinate).withLocation(location)
        cachedSnapshot = snapshot
        return snapshot
    }

    public func cached() -> WeatherSnapshot? {
        cachedSnapshot
    }
}
