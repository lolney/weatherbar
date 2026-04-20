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

        let observed = try? await currentObservation(
            stationsURLString: points.properties.observationStations,
            coordinate: coordinate,
            fallbackPeriod: currentPeriod
        )

        let current = observed ?? CurrentWeather(
            temperatureF: currentPeriod.temperature,
            apparentTemperatureF: currentPeriod.temperature,
            condition: WeatherCondition.classify(currentPeriod.shortForecast),
            summary: currentPeriod.shortForecast,
            precipitationChance: currentPeriod.probabilityOfPrecipitation.intValue,
            wind: currentPeriod.wind,
            source: "NWS hourly forecast"
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
            locationName: points.properties.relativeLocation?.properties.displayName,
            coordinate: coordinate
        )
    }

    private func currentObservation(
        stationsURLString: String?,
        coordinate: Coordinate,
        fallbackPeriod: NWSPeriod
    ) async throws -> CurrentWeather? {
        guard let stationsURLString,
              let stationsURL = URL(string: stationsURLString) else { return nil }
        let stations = try await get(StationsResponse.self, url: stationsURL)

        for feature in stations.features.prefix(5) {
            guard let observationURL = URL(string: "\(feature.properties.stationURL)/observations/latest") else {
                continue
            }

            let observation = try? await get(ObservationResponse.self, url: observationURL)
            guard let observation,
                  let tempC = observation.properties.temperature.value else {
                continue
            }

            let station = ObservationStation(
                identifier: feature.properties.stationIdentifier,
                name: feature.properties.name,
                distanceMiles: feature.distanceMiles(from: coordinate)
            )
            let summary = observation.properties.textDescription?.nilIfBlank ?? fallbackPeriod.shortForecast
            return CurrentWeather(
                temperatureF: Self.celsiusToFahrenheit(tempC),
                apparentTemperatureF: observation.properties.heatIndex.value.map(Self.celsiusToFahrenheit)
                    ?? observation.properties.windChill.value.map(Self.celsiusToFahrenheit),
                condition: WeatherCondition.classify(summary),
                summary: summary,
                precipitationChance: fallbackPeriod.probabilityOfPrecipitation.intValue,
                humidity: observation.properties.relativeHumidity.value.map { Int($0.rounded()) },
                dewPointF: observation.properties.dewpoint.value.map(Self.celsiusToFahrenheit),
                wind: Wind(
                    speedMph: observation.properties.windSpeed.value.map(Self.metersPerSecondToMilesPerHour),
                    directionDegrees: observation.properties.windDirection.value.map { Int($0.rounded()) },
                    directionText: observation.properties.windDirection.value.map { Wind.cardinalDirection(Int($0.rounded())) },
                    gustMph: observation.properties.windGust.value.map(Self.metersPerSecondToMilesPerHour)
                ),
                observationStation: station,
                observedAt: observation.properties.timestamp,
                source: "NWS station observation"
            )
        }

        return nil
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
            let precip = dayPeriods.compactMap { $0.probabilityOfPrecipitation.intValue }.max()
            let representative = dayPeriods.first(where: { $0.isDaytime }) ?? first

            let hourly = dayPeriods.map { period in
                HourlyForecast(
                    startTime: period.startTime,
                    temperatureF: period.temperature,
                    precipitationChance: period.probabilityOfPrecipitation.intValue,
                    condition: WeatherCondition.classify(period.shortForecast),
                    summary: period.shortForecast,
                    wind: period.wind
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
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func celsiusToFahrenheit(_ celsius: Double) -> Int {
        Int((celsius * 9 / 5 + 32).rounded())
    }

    private static func metersPerSecondToMilesPerHour(_ metersPerSecond: Double) -> Double {
        metersPerSecond * 2.2369362921
    }
}

public struct PointsResponse: Decodable {
    public let properties: PointsProperties
}

public struct PointsProperties: Decodable {
    public let forecastHourly: String
    public let observationStations: String?
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

    public var wind: Wind {
        Wind(
            speedMph: Double(windSpeed.split(separator: " ").first ?? ""),
            directionDegrees: nil,
            directionText: windDirection
        )
    }
}

public struct QuantitativeValue: Decodable, Equatable {
    public let value: Double?

    public init(value: Double?) {
        self.value = value
    }

    public var intValue: Int? {
        value.map { Int($0.rounded()) }
    }
}

public struct StationsResponse: Decodable {
    public let features: [StationFeature]
}

public struct StationFeature: Decodable {
    public let geometry: StationGeometry
    public let properties: StationProperties

    public func distanceMiles(from coordinate: Coordinate) -> Double? {
        guard geometry.coordinates.count >= 2 else { return nil }
        let longitude = geometry.coordinates[0]
        let latitude = geometry.coordinates[1]
        return haversineMiles(
            lat1: coordinate.latitude,
            lon1: coordinate.longitude,
            lat2: latitude,
            lon2: longitude
        )
    }

    private func haversineMiles(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6371.0088
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * asin(sqrt(a)) * 0.621371
    }
}

public struct StationGeometry: Decodable {
    public let coordinates: [Double]
}

public struct StationProperties: Decodable {
    public let stationIdentifier: String
    public let name: String
    public let stationURL: String

    enum CodingKeys: String, CodingKey {
        case stationIdentifier
        case name
        case stationURL = "@id"
    }
}

public struct ObservationResponse: Decodable {
    public let properties: ObservationProperties
}

public struct ObservationProperties: Decodable {
    public let timestamp: Date
    public let textDescription: String?
    public let temperature: DoubleQuantitativeValue
    public let dewpoint: DoubleQuantitativeValue
    public let windDirection: DoubleQuantitativeValue
    public let windSpeed: DoubleQuantitativeValue
    public let windGust: DoubleQuantitativeValue
    public let relativeHumidity: DoubleQuantitativeValue
    public let windChill: DoubleQuantitativeValue
    public let heatIndex: DoubleQuantitativeValue
}

public struct DoubleQuantitativeValue: Decodable, Equatable {
    public let value: Double?
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
