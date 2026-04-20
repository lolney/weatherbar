import XCTest
@testable import WeatherBarCore

final class NWSWeatherProviderTests: XCTestCase {
    func testClassifiesCommonConditions() {
        XCTAssertEqual(WeatherCondition.classify("Sunny"), .sunny)
        XCTAssertEqual(WeatherCondition.classify("Patchy Fog"), .fog)
        XCTAssertEqual(WeatherCondition.classify("Rain Showers"), .rain)
        XCTAssertEqual(WeatherCondition.classify("Snow Likely"), .snow)
        XCTAssertEqual(WeatherCondition.classify("Thunderstorms"), .thunderstorm)
    }

    func testDailyForecastsGroupHourlyPeriodsIntoSevenDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = ISO8601DateFormatter().date(from: "2026-04-19T00:00:00Z")!

        var periods: [NWSPeriod] = []
        for day in 0..<8 {
            for hour in [6, 12, 18] {
                let date = calendar.date(byAdding: .hour, value: day * 24 + hour, to: start)!
                let end = calendar.date(byAdding: .hour, value: 1, to: date)!
                periods.append(
                    NWSPeriod(
                        number: periods.count + 1,
                        name: "Hour",
                        startTime: date,
                        endTime: end,
                        isDaytime: hour == 12,
                        temperature: 50 + day + hour / 6,
                        temperatureUnit: "F",
                        probabilityOfPrecipitation: QuantitativeValue(value: Double(day * 10)),
                        windSpeed: "5 mph",
                        windDirection: "NW",
                        shortForecast: hour == 12 ? "Sunny" : "Mostly Cloudy",
                        detailedForecast: "Detailed"
                    )
                )
            }
        }

        let daily = NWSWeatherProvider.dailyForecasts(from: periods, calendar: calendar)

        XCTAssertEqual(daily.count, 7)
        XCTAssertEqual(daily[0].lowF, 51)
        XCTAssertEqual(daily[0].highF, 53)
        XCTAssertEqual(daily[0].precipitationChance, 0)
        XCTAssertEqual(daily[0].condition, .sunny)
        XCTAssertEqual(daily[0].hourly.count, 3)
    }

    func testFetchWeatherUsesPointsAndHourlyEndpoints() async throws {
        let http = MockHTTPClient()
        http.responses = [
            "/points/37.7749,-122.4194": pointsJSON,
            "/gridpoints/MTR/85,105/forecast/hourly": hourlyJSON
        ]

        let provider = NWSWeatherProvider(
            httpClient: http,
            baseURL: URL(string: "https://api.weather.gov")!,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7749, longitude: -122.4194))

        XCTAssertEqual(snapshot.current.temperatureF, 61)
        XCTAssertEqual(snapshot.current.condition, .fog)
        XCTAssertEqual(snapshot.locationName, "San Francisco, CA")
        XCTAssertEqual(snapshot.daily.first?.highF, 64)
        XCTAssertTrue(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") != nil })
    }

    func testFetchWeatherDoesNotRequireObservationStations() async throws {
        let http = MockHTTPClient()
        http.responses = [
            "/points/37.7749,-122.4194": pointsWithoutStationsJSON,
            "/gridpoints/MTR/85,105/forecast/hourly": hourlyJSON
        ]

        let provider = NWSWeatherProvider(
            httpClient: http,
            baseURL: URL(string: "https://api.weather.gov")!,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7749, longitude: -122.4194))

        XCTAssertEqual(snapshot.current.source, "NWS hourly forecast")
        XCTAssertEqual(snapshot.current.temperatureF, 61)
        XCTAssertNil(snapshot.current.observationStation)
    }

    func testPointsRequestUsesLocaleIndependentDecimalSeparators() async throws {
        let http = MockHTTPClient()
        http.responses = [
            "/points/37.7749,-122.4194": pointsWithoutStationsJSON,
            "/gridpoints/MTR/85,105/forecast/hourly": hourlyJSON
        ]
        let provider = NWSWeatherProvider(
            httpClient: http,
            baseURL: URL(string: "https://api.weather.gov")!,
            calendar: Calendar(identifier: .gregorian)
        )

        _ = try await provider.fetchWeather(for: Coordinate(latitude: 37.7749, longitude: -122.4194))

        XCTAssertEqual(http.requests.first?.url?.path, "/points/37.7749,-122.4194")
    }

    func testFetchWeatherUsesNearestStationObservationForCurrentConditions() async throws {
        let http = MockHTTPClient()
        http.responses = [
            "/points/37.7749,-122.4194": pointsJSON,
            "/gridpoints/MTR/85,105/forecast/hourly": hourlyJSON,
            "/gridpoints/MTR/85,105/stations": stationsJSON,
            "/stations/SFOC1/observations/latest": observationJSON
        ]

        let provider = NWSWeatherProvider(
            httpClient: http,
            baseURL: URL(string: "https://api.weather.gov")!,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7749, longitude: -122.4194))

        XCTAssertEqual(snapshot.current.temperatureF, 55)
        XCTAssertEqual(snapshot.current.condition, .fog)
        XCTAssertEqual(snapshot.current.source, "NWS station observation")
        XCTAssertEqual(snapshot.current.observationStation?.identifier, "SFOC1")
        XCTAssertEqual(snapshot.current.humidity, 86)
        XCTAssertEqual(snapshot.current.dewPointF, 52)
    }
}

private final class MockHTTPClient: HTTPClient {
    var responses: [String: String] = [:]
    var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard let body = responses[request.url!.path] else {
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private let pointsJSON = """
{
  "properties": {
    "forecastHourly": "https://api.weather.gov/gridpoints/MTR/85,105/forecast/hourly",
    "observationStations": "https://api.weather.gov/gridpoints/MTR/85,105/stations",
    "relativeLocation": {
      "properties": {
        "city": "San Francisco",
        "state": "CA"
      }
    }
  }
}
"""

private let pointsWithoutStationsJSON = """
{
  "properties": {
    "forecastHourly": "https://api.weather.gov/gridpoints/MTR/85,105/forecast/hourly",
    "relativeLocation": {
      "properties": {
        "city": "San Francisco",
        "state": "CA"
      }
    }
  }
}
"""

private let hourlyJSON = """
{
  "properties": {
    "periods": [
      {
        "number": 1,
        "name": "Now",
        "startTime": "2026-04-19T09:00:00-07:00",
        "endTime": "2026-04-19T10:00:00-07:00",
        "isDaytime": true,
        "temperature": 61,
        "temperatureUnit": "F",
        "probabilityOfPrecipitation": { "value": 10 },
        "windSpeed": "6 mph",
        "windDirection": "W",
        "shortForecast": "Patchy Fog",
        "detailedForecast": "Patchy fog before noon."
      },
      {
        "number": 2,
        "name": "Later",
        "startTime": "2026-04-19T14:00:00-07:00",
        "endTime": "2026-04-19T15:00:00-07:00",
        "isDaytime": true,
        "temperature": 64,
        "temperatureUnit": "F",
        "probabilityOfPrecipitation": { "value": 20 },
        "windSpeed": "10 mph",
        "windDirection": "W",
        "shortForecast": "Sunny",
        "detailedForecast": "Sunny."
      }
    ]
  }
}
"""

private let stationsJSON = """
{
  "features": [
    {
      "geometry": {
        "coordinates": [-122.4269, 37.8060]
      },
      "properties": {
        "stationIdentifier": "SFOC1",
        "name": "San Francisco Downtown",
        "@id": "https://api.weather.gov/stations/SFOC1"
      }
    }
  ]
}
"""

private let observationJSON = """
{
  "properties": {
    "timestamp": "2026-04-19T16:00:00Z",
    "textDescription": "Fog/Mist",
    "temperature": { "value": 12.8 },
    "dewpoint": { "value": 11.2 },
    "windDirection": { "value": 250 },
    "windSpeed": { "value": 5 },
    "windGust": { "value": 8 },
    "relativeHumidity": { "value": 86 },
    "windChill": { "value": null },
    "heatIndex": { "value": null }
  }
}
"""
