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
    func currentCoordinate() async throws -> Coordinate {
        Coordinate(latitude: 37.0, longitude: -122.0)
    }
}
