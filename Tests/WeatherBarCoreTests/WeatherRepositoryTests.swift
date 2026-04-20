import XCTest
@testable import WeatherBarCore

final class WeatherRepositoryTests: XCTestCase {
    func testRefreshUsesCachedSnapshotWithinTTL() async throws {
        var currentDate = Date(timeIntervalSince1970: 100)
        let provider = FakeProvider()
        let repository = WeatherRepository(
            provider: provider,
            locationProvider: StaticLocationProvider(),
            ttl: 600,
            now: { currentDate }
        )

        let first = try await repository.refresh()
        currentDate = Date(timeIntervalSince1970: 200)
        let second = try await repository.refresh()

        XCTAssertEqual(first, second)
        XCTAssertEqual(provider.callCount, 1)
    }

    func testRefreshCanForcePastCache() async throws {
        let provider = FakeProvider()
        let repository = WeatherRepository(
            provider: provider,
            locationProvider: StaticLocationProvider()
        )

        _ = try await repository.refresh()
        _ = try await repository.refresh(force: true)

        XCTAssertEqual(provider.callCount, 2)
    }

    func testConcurrentRefreshesShareInFlightFetch() async throws {
        let provider = CountingProvider()
        let locationProvider = BlockingLocationProvider()
        let repository = WeatherRepository(
            provider: provider,
            locationProvider: locationProvider
        )

        let first = Task { try await repository.refresh(force: true) }
        await locationProvider.waitForCallCount(1)

        let second = Task { try await repository.refresh(force: true) }
        try await Task.sleep(nanoseconds: 50_000_000)

        let locationCallCount = await locationProvider.currentCallCount()
        XCTAssertEqual(locationCallCount, 1)

        await locationProvider.resumeAll()
        _ = try await first.value
        _ = try await second.value

        let providerCallCount = await provider.currentCallCount()
        XCTAssertEqual(providerCallCount, 1)
    }
}

private final class FakeProvider: WeatherProvider {
    var callCount = 0

    func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        callCount += 1
        return WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 60 + callCount,
                condition: .sunny,
                summary: "Sunny",
                precipitationChance: 0
            ),
            daily: [],
            fetchedAt: Date(timeIntervalSince1970: 100),
            sourceDescription: "Fake",
            locationName: "Test"
        )
    }
}

private struct StaticLocationProvider: LocationProviding {
    func currentLocation() async throws -> LocationFix {
        LocationFix(
            coordinate: Coordinate(latitude: 37.0, longitude: -122.0),
            horizontalAccuracyMeters: 25,
            displayName: "Test",
            resolvedAt: Date()
        )
    }
}

private actor CountingProvider: WeatherProvider {
    private var callCount = 0

    func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        callCount += 1
        return WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 60,
                condition: .sunny,
                summary: "Sunny",
                precipitationChance: 0
            ),
            daily: [],
            fetchedAt: Date(timeIntervalSince1970: 100),
            sourceDescription: "Fake",
            locationName: "Test"
        )
    }

    func currentCallCount() -> Int {
        callCount
    }
}

private actor BlockingLocationProvider: LocationProviding {
    private var callCount = 0
    private var continuations: [CheckedContinuation<LocationFix, Never>] = []

    func currentLocation() async throws -> LocationFix {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ expectedCount: Int) async {
        while callCount < expectedCount {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func resumeAll() {
        let continuations = continuations
        self.continuations.removeAll()
        continuations.forEach { continuation in
            continuation.resume(returning: LocationFix(
                coordinate: Coordinate(latitude: 37.0, longitude: -122.0),
                horizontalAccuracyMeters: 25,
                displayName: "Test",
                resolvedAt: Date()
            ))
        }
    }

    func currentCallCount() -> Int {
        callCount
    }
}
