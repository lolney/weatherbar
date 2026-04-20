import Foundation

public actor WeatherRepository {
    private let provider: WeatherProvider
    private let locationProvider: LocationProviding
    private let ttl: TimeInterval
    private let now: () -> Date
    private var cachedSnapshot: WeatherSnapshot?
    private var inFlightRefresh: Task<WeatherSnapshot, Error>?

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

        if let inFlightRefresh {
            return try await inFlightRefresh.value
        }

        let task = Task { [locationProvider, provider] in
            let location = try await locationProvider.currentLocation()
            return try await provider.fetchWeather(for: location.coordinate).withLocation(location)
        }
        inFlightRefresh = task

        do {
            let snapshot = try await task.value
            cachedSnapshot = snapshot
            inFlightRefresh = nil
            return snapshot
        } catch {
            inFlightRefresh = nil
            throw error
        }
    }

    public func cached() -> WeatherSnapshot? {
        cachedSnapshot
    }
}
