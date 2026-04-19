import Foundation

public final class NWSWeatherProvider: WeatherProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL
    private let userAgent: String
    private let calendar: Calendar

    public init(
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = URL(string: "https://api.weather.gov")!,
        userAgent: String = "WeatherBarMVP/1.0 (personal macOS menu bar weather app)",
        calendar: Calendar = .current
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.calendar = calendar
    }

    public func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        let points = try await get(
            PointsResponse.self,
            path: "/points/\(format(coordinate.latitude)),\(format(coordinate.longitude))"
        )

        guard let hourlyURL = URL(string: points.properties.forecastHourly) else {
            throw WeatherError.invalidResponse
        }

        let hourly = try await get(HourlyResponse.self, url: hourlyURL)
        let periods = hourly.properties.periods
        guard let currentPeriod = periods.first else {
            throw WeatherError.noForecast
        }

        let current = CurrentWeather(
            temperatureF: currentPeriod.temperature,
            condition: WeatherCondition.classify(currentPeriod.shortForecast),
            summary: currentPeriod.shortForecast,
            precipitationChance: currentPeriod.probabilityOfPrecipitation.value
        )

        let daily = Self.dailyForecasts(from: periods, calendar: calendar)
        guard !daily.isEmpty else {
            throw WeatherError.noForecast
        }

        return WeatherSnapshot(
            current: current,
            daily: daily,
            fetchedAt: Date(),
            sourceDescription: "National Weather Service",
            locationName: points.properties.relativeLocation?.properties.displayName
        )
    }

    public static func dailyForecasts(from periods: [NWSPeriod], calendar: Calendar) -> [DailyForecast] {
        let grouped = Dictionary(grouping: periods) { period in
            calendar.startOfDay(for: period.startTime)
        }

        return grouped.keys.sorted().prefix(7).compactMap { day in
            guard let dayPeriods = grouped[day]?.sorted(by: { $0.startTime < $1.startTime }),
                  let first = dayPeriods.first else {
                return nil
            }

            let high = dayPeriods.map(\.temperature).max() ?? first.temperature
            let low = dayPeriods.map(\.temperature).min() ?? first.temperature
            let precip = dayPeriods.compactMap { $0.probabilityOfPrecipitation.value }.max()
            let representative = dayPeriods.first(where: { $0.isDaytime }) ?? first

            let hourly = dayPeriods.map { period in
                HourlyForecast(
                    startTime: period.startTime,
                    temperatureF: period.temperature,
                    precipitationChance: period.probabilityOfPrecipitation.value,
                    condition: WeatherCondition.classify(period.shortForecast),
                    summary: period.shortForecast,
                    wind: "\(period.windSpeed) \(period.windDirection)"
                )
            }

            return DailyForecast(
                date: day,
                highF: high,
                lowF: low,
                precipitationChance: precip,
                condition: WeatherCondition.classify(representative.shortForecast),
                summary: representative.shortForecast,
                hourly: hourly
            )
        }
    }

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        try await get(type, url: baseURL.appendingPathComponent(path))
    }

    private func get<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json, application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 {
                throw WeatherError.unsupportedLocation("NWS weather data is only available for supported US locations.")
            }
            throw WeatherError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }
}

public struct PointsResponse: Decodable {
    public let properties: PointsProperties
}

public struct PointsProperties: Decodable {
    public let forecastHourly: String
    public let relativeLocation: RelativeLocation?
}

public struct RelativeLocation: Decodable {
    public let properties: RelativeLocationProperties
}

public struct RelativeLocationProperties: Decodable {
    public let city: String?
    public let state: String?

    public var displayName: String? {
        switch (city, state) {
        case let (city?, state?):
            return "\(city), \(state)"
        case let (city?, nil):
            return city
        case let (nil, state?):
            return state
        default:
            return nil
        }
    }
}

public struct HourlyResponse: Decodable {
    public let properties: HourlyProperties
}

public struct HourlyProperties: Decodable {
    public let periods: [NWSPeriod]
}

public struct NWSPeriod: Decodable, Equatable {
    public let number: Int
    public let name: String
    public let startTime: Date
    public let endTime: Date
    public let isDaytime: Bool
    public let temperature: Int
    public let temperatureUnit: String
    public let probabilityOfPrecipitation: QuantitativeValue
    public let windSpeed: String
    public let windDirection: String
    public let shortForecast: String
    public let detailedForecast: String

    public init(
        number: Int,
        name: String,
        startTime: Date,
        endTime: Date,
        isDaytime: Bool,
        temperature: Int,
        temperatureUnit: String,
        probabilityOfPrecipitation: QuantitativeValue,
        windSpeed: String,
        windDirection: String,
        shortForecast: String,
        detailedForecast: String
    ) {
        self.number = number
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.isDaytime = isDaytime
        self.temperature = temperature
        self.temperatureUnit = temperatureUnit
        self.probabilityOfPrecipitation = probabilityOfPrecipitation
        self.windSpeed = windSpeed
        self.windDirection = windDirection
        self.shortForecast = shortForecast
        self.detailedForecast = detailedForecast
    }
}

public struct QuantitativeValue: Decodable, Equatable {
    public let value: Int?

    public init(value: Int?) {
        self.value = value
    }
}
