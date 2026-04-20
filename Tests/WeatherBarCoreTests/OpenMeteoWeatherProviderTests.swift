import XCTest
@testable import WeatherBarCore

final class OpenMeteoWeatherProviderTests: XCTestCase {
    func testFetchWeatherDecodesCurrentDailyAndHourlyDetails() async throws {
        let http = MockOpenMeteoHTTPClient(response: openMeteoJSON)
        let provider = OpenMeteoWeatherProvider(
            httpClient: http,
            baseURL: URL(string: "https://api.open-meteo.com/v1/forecast")!,
            calendar: Calendar(identifier: .gregorian)
        )

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7651, longitude: -122.4497))

        XCTAssertEqual(snapshot.current.temperatureF, 64)
        XCTAssertEqual(snapshot.current.apparentTemperatureF, 52)
        XCTAssertEqual(snapshot.current.condition, .partlyCloudy)
        XCTAssertEqual(snapshot.current.humidity, 61)
        XCTAssertEqual(snapshot.current.wind?.directionText, "WSW")
        XCTAssertEqual(snapshot.daily.count, 1)
        XCTAssertEqual(snapshot.daily[0].uvIndexMax, 7.5)
        XCTAssertEqual(snapshot.daily[0].precipitationAmountInches, 0.01)
        XCTAssertEqual(snapshot.daily[0].hourly.count, 2)
        XCTAssertEqual(snapshot.daily[0].hourly[0].uvIndex, 4.0)
        XCTAssertEqual(snapshot.daily[0].hourly[0].humidity, 62)
        XCTAssertTrue(http.requests.first?.url?.query?.contains("uv_index") == true)
    }

    func testCompositeProviderKeepsPrimaryForecastAndMergesSupplementalDetails() async throws {
        let day = date("2026-04-19T00:00:00-07:00")
        let hour = date("2026-04-19T17:00:00-07:00")
        let primary = StaticProvider(snapshot: WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 61,
                condition: .fog,
                summary: "Patchy Fog",
                precipitationChance: nil
            ),
            daily: [
                DailyForecast(
                    date: day,
                    highF: 64,
                    lowF: 55,
                    precipitationChance: nil,
                    condition: .fog,
                    summary: "Patchy Fog",
                    hourly: [
                        HourlyForecast(
                            startTime: hour,
                            temperatureF: 61,
                            precipitationChance: nil,
                            condition: .fog,
                            summary: "Patchy Fog"
                        )
                    ]
                )
            ],
            fetchedAt: date("2026-04-19T17:00:00-07:00"),
            sourceDescription: "National Weather Service",
            locationName: "San Francisco, CA"
        ))
        let supplement = StaticProvider(snapshot: WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 64,
                apparentTemperatureF: 52,
                condition: .partlyCloudy,
                summary: "Partly Cloudy",
                precipitationChance: 1,
                humidity: 61,
                wind: Wind(speedMph: 14, directionDegrees: 247, directionText: "WSW")
            ),
            daily: [
                DailyForecast(
                    date: day,
                    highF: 62,
                    lowF: 55,
                    precipitationChance: 4,
                    precipitationAmountInches: 0.01,
                    condition: .partlyCloudy,
                    summary: "Partly Cloudy",
                    sunrise: date("2026-04-19T06:28:00-07:00"),
                    sunset: date("2026-04-19T19:49:00-07:00"),
                    daylightDurationSeconds: 48_060,
                    uvIndexMax: 7.5,
                    apparentHighF: 65,
                    apparentLowF: 46,
                    wind: Wind(speedMph: 14, directionDegrees: 247, directionText: "WSW", gustMph: 24),
                    hourly: [
                        HourlyForecast(
                            startTime: hour,
                            temperatureF: 62,
                            precipitationChance: 1,
                            uvIndex: 4.0,
                            humidity: 62,
                            condition: .partlyCloudy,
                            summary: "Partly Cloudy",
                            wind: Wind(speedMph: 14, directionDegrees: 247, directionText: "WSW", gustMph: 22)
                        )
                    ]
                )
            ],
            fetchedAt: date("2026-04-19T17:00:00-07:00"),
            sourceDescription: "Open-Meteo",
            locationName: nil
        ))
        let provider = CompositeWeatherProvider(primary: primary, supplement: supplement)

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7651, longitude: -122.4497))

        XCTAssertEqual(snapshot.current.temperatureF, 61)
        XCTAssertEqual(snapshot.current.summary, "Patchy Fog")
        XCTAssertEqual(snapshot.current.apparentTemperatureF, 52)
        XCTAssertEqual(snapshot.current.humidity, 61)
        XCTAssertEqual(snapshot.sourceDescription, "National Weather Service + Open-Meteo details")
        XCTAssertEqual(snapshot.daily[0].highF, 64)
        XCTAssertEqual(snapshot.daily[0].precipitationChance, 4)
        XCTAssertEqual(snapshot.daily[0].uvIndexMax, 7.5)
        XCTAssertEqual(snapshot.daily[0].hourly[0].uvIndex, 4.0)
        XCTAssertEqual(snapshot.daily[0].hourly[0].humidity, 62)
    }

    func testCompositeProviderToleratesDuplicateSupplementalHourlyTimestamps() async throws {
        let day = date("2026-11-01T00:00:00-07:00")
        let repeatedHour = date("2026-11-01T01:00:00-07:00")
        let primary = StaticProvider(snapshot: WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 50,
                condition: .cloudy,
                summary: "Cloudy",
                precipitationChance: nil
            ),
            daily: [
                DailyForecast(
                    date: day,
                    highF: 55,
                    lowF: 47,
                    precipitationChance: nil,
                    condition: .cloudy,
                    summary: "Cloudy",
                    hourly: [
                        HourlyForecast(
                            startTime: repeatedHour,
                            temperatureF: 50,
                            precipitationChance: nil,
                            condition: .cloudy,
                            summary: "Cloudy"
                        )
                    ]
                )
            ],
            fetchedAt: repeatedHour,
            sourceDescription: "National Weather Service",
            locationName: "Test"
        ))
        let supplement = StaticProvider(snapshot: WeatherSnapshot(
            current: CurrentWeather(
                temperatureF: 51,
                condition: .partlyCloudy,
                summary: "Partly Cloudy",
                precipitationChance: nil
            ),
            daily: [
                DailyForecast(
                    date: day,
                    highF: 56,
                    lowF: 48,
                    precipitationChance: 20,
                    condition: .partlyCloudy,
                    summary: "Partly Cloudy",
                    hourly: [
                        HourlyForecast(
                            startTime: repeatedHour,
                            temperatureF: 51,
                            precipitationChance: 10,
                            uvIndex: 1.0,
                            humidity: 70,
                            condition: .partlyCloudy,
                            summary: "Partly Cloudy"
                        ),
                        HourlyForecast(
                            startTime: repeatedHour,
                            temperatureF: 52,
                            precipitationChance: 30,
                            uvIndex: 2.0,
                            humidity: 75,
                            condition: .rain,
                            summary: "Rain"
                        )
                    ]
                )
            ],
            fetchedAt: repeatedHour,
            sourceDescription: "Open-Meteo",
            locationName: nil
        ))
        let provider = CompositeWeatherProvider(primary: primary, supplement: supplement)

        let snapshot = try await provider.fetchWeather(for: Coordinate(latitude: 37.7651, longitude: -122.4497))

        XCTAssertEqual(snapshot.daily[0].hourly[0].uvIndex, 2.0)
        XCTAssertEqual(snapshot.daily[0].hourly[0].humidity, 75)
        XCTAssertEqual(snapshot.daily[0].hourly[0].precipitationChance, 30)
        XCTAssertEqual(snapshot.daily[0].hourly[0].condition, .cloudy)
    }
}

private final class MockOpenMeteoHTTPClient: HTTPClient {
    let response: String
    var requests: [URLRequest] = []

    init(response: String) {
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(self.response.utf8), response)
    }
}

private final class StaticProvider: WeatherProvider {
    let snapshot: WeatherSnapshot

    init(snapshot: WeatherSnapshot) {
        self.snapshot = snapshot
    }

    func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        snapshot
    }
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private let openMeteoJSON = """
{
  "timezone": "America/Los_Angeles",
  "current": {
    "time": "2026-04-19T17:00",
    "temperature_2m": 63.6,
    "relative_humidity_2m": 61,
    "apparent_temperature": 52.4,
    "precipitation": 0,
    "weather_code": 2,
    "cloud_cover": 52,
    "wind_speed_10m": 14.2,
    "wind_direction_10m": 247,
    "wind_gusts_10m": 22.1,
    "is_day": 1
  },
  "hourly": {
    "time": ["2026-04-19T17:00", "2026-04-19T18:00"],
    "temperature_2m": [62.1, 60.4],
    "apparent_temperature": [52.1, 50.5],
    "precipitation_probability": [1, 2],
    "weather_code": [2, 3],
    "relative_humidity_2m": [62, 64],
    "dew_point_2m": [49.2, 49.0],
    "uv_index": [4.0, 2.1],
    "cloud_cover": [51, 72],
    "visibility": [40000, 38000],
    "wind_speed_10m": [14.0, 13.2],
    "wind_direction_10m": [247, 250],
    "wind_gusts_10m": [22.0, 23.0]
  },
  "daily": {
    "time": ["2026-04-19"],
    "weather_code": [2],
    "temperature_2m_max": [62.1],
    "temperature_2m_min": [55.2],
    "apparent_temperature_max": [65.1],
    "apparent_temperature_min": [46.2],
    "precipitation_probability_max": [4],
    "precipitation_sum": [0.01],
    "sunrise": ["2026-04-19T06:28"],
    "sunset": ["2026-04-19T19:49"],
    "uv_index_max": [7.5],
    "wind_speed_10m_max": [14.4],
    "wind_gusts_10m_max": [24.1],
    "wind_direction_10m_dominant": [247],
    "daylight_duration": [48060]
  }
}
"""
