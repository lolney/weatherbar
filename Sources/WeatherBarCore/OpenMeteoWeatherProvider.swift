import Foundation

public final class OpenMeteoWeatherProvider: WeatherProvider {
    private let httpClient: HTTPClient
    private let baseURL: URL
    private let calendar: Calendar

    public init(
        httpClient: HTTPClient = URLSessionHTTPClient(),
        baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!,
        calendar: Calendar = .current
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.calendar = calendar
    }

    public func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(coordinate.longitude)"),
            URLQueryItem(name: "current", value: [
                "temperature_2m",
                "relative_humidity_2m",
                "apparent_temperature",
                "precipitation",
                "weather_code",
                "cloud_cover",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m",
                "is_day"
            ].joined(separator: ",")),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m",
                "apparent_temperature",
                "precipitation_probability",
                "weather_code",
                "relative_humidity_2m",
                "dew_point_2m",
                "uv_index",
                "cloud_cover",
                "visibility",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m"
            ].joined(separator: ",")),
            URLQueryItem(name: "daily", value: [
                "weather_code",
                "temperature_2m_max",
                "temperature_2m_min",
                "apparent_temperature_max",
                "apparent_temperature_min",
                "precipitation_probability_max",
                "precipitation_sum",
                "sunrise",
                "sunset",
                "uv_index_max",
                "wind_speed_10m_max",
                "wind_gusts_10m_max",
                "wind_direction_10m_dominant",
                "daylight_duration"
            ].joined(separator: ",")),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]

        guard let url = components.url else {
            throw WeatherError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("WeatherBarMVP/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw WeatherError.invalidResponse
        }

        let responseBody = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return try responseBody.snapshot(coordinate: coordinate, calendar: calendar)
    }
}

public final class CompositeWeatherProvider: WeatherProvider {
    private let primary: WeatherProvider
    private let supplement: WeatherProvider

    public init(primary: WeatherProvider, supplement: WeatherProvider) {
        self.primary = primary
        self.supplement = supplement
    }

    public func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot {
        async let primaryResult = capture { try await self.primary.fetchWeather(for: coordinate) }
        async let supplementResult = capture { try await self.supplement.fetchWeather(for: coordinate) }

        let primarySnapshot = await primaryResult
        let supplementSnapshot = await supplementResult

        switch (primarySnapshot, supplementSnapshot) {
        case let (.success(primary), .success(supplement)):
            return primary.mergingDetails(from: supplement)
        case let (.success(primary), .failure):
            return primary
        case let (.failure, .success(supplement)):
            return supplement
        case let (.failure(error), .failure):
            throw error
        }
    }

    private func capture(_ operation: @escaping () async throws -> WeatherSnapshot) async -> Result<WeatherSnapshot, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}

private extension WeatherSnapshot {
    func mergingDetails(from supplement: WeatherSnapshot) -> WeatherSnapshot {
        let supplementalDays = Dictionary(uniqueKeysWithValues: supplement.daily.map { ($0.date, $0) })
        let mergedDays = daily.map { day in
            guard let supplemental = supplementalDays[day.date] else { return day }
            return DailyForecast(
                date: day.date,
                highF: day.highF,
                lowF: day.lowF,
                precipitationChance: day.precipitationChance ?? supplemental.precipitationChance,
                precipitationAmountInches: supplemental.precipitationAmountInches,
                condition: day.condition,
                summary: day.summary,
                sunrise: supplemental.sunrise,
                sunset: supplemental.sunset,
                daylightDurationSeconds: supplemental.daylightDurationSeconds,
                uvIndexMax: supplemental.uvIndexMax,
                apparentHighF: supplemental.apparentHighF,
                apparentLowF: supplemental.apparentLowF,
                wind: supplemental.wind ?? day.wind,
                hourly: mergeHourly(primary: day.hourly, supplemental: supplemental.hourly)
            )
        }

        return WeatherSnapshot(
            current: current.enriched(from: supplement.current),
            daily: mergedDays.isEmpty ? supplement.daily : mergedDays,
            fetchedAt: fetchedAt,
            sourceDescription: "\(sourceDescription) + Open-Meteo details",
            locationName: locationName,
            coordinate: coordinate,
            locationAccuracyMeters: locationAccuracyMeters
        )
    }

    func mergeHourly(primary: [HourlyForecast], supplemental: [HourlyForecast]) -> [HourlyForecast] {
        let supplementalByHour = Dictionary(uniqueKeysWithValues: supplemental.map { ($0.startTime, $0) })
        return primary.map { hour in
            guard let detail = supplementalByHour[hour.startTime] else { return hour }
            return HourlyForecast(
                startTime: hour.startTime,
                temperatureF: hour.temperatureF,
                apparentTemperatureF: detail.apparentTemperatureF,
                precipitationChance: hour.precipitationChance ?? detail.precipitationChance,
                uvIndex: detail.uvIndex,
                humidity: detail.humidity,
                dewPointF: detail.dewPointF,
                cloudCover: detail.cloudCover,
                visibilityFeet: detail.visibilityFeet,
                condition: hour.condition,
                summary: hour.summary,
                wind: detail.wind ?? hour.wind
            )
        }
    }
}

private extension CurrentWeather {
    func enriched(from supplement: CurrentWeather) -> CurrentWeather {
        CurrentWeather(
            temperatureF: temperatureF,
            apparentTemperatureF: apparentTemperatureF ?? supplement.apparentTemperatureF,
            condition: condition == .unknown ? supplement.condition : condition,
            summary: summary.isEmpty ? supplement.summary : summary,
            precipitationChance: precipitationChance ?? supplement.precipitationChance,
            humidity: humidity ?? supplement.humidity,
            dewPointF: dewPointF ?? supplement.dewPointF,
            cloudCover: cloudCover ?? supplement.cloudCover,
            wind: wind ?? supplement.wind,
            observationStation: observationStation,
            observedAt: observedAt,
            source: source
        )
    }
}

public struct OpenMeteoResponse: Decodable {
    public let timezone: String
    public let current: OpenMeteoCurrent
    public let hourly: OpenMeteoHourly
    public let daily: OpenMeteoDaily

    public func snapshot(coordinate: Coordinate, calendar: Calendar) throws -> WeatherSnapshot {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: timezone) ?? calendar.timeZone

        let currentCode = current.weatherCode
        let current = CurrentWeather(
            temperatureF: Int(self.current.temperature.rounded()),
            apparentTemperatureF: self.current.apparentTemperature.map { Int($0.rounded()) },
            condition: WeatherCondition.fromWMOCode(currentCode),
            summary: WeatherCondition.wmoSummary(currentCode),
            precipitationChance: nil,
            humidity: self.current.relativeHumidity,
            dewPointF: nil,
            cloudCover: self.current.cloudCover,
            wind: Wind(
                speedMph: self.current.windSpeed,
                directionDegrees: self.current.windDirection,
                directionText: self.current.windDirection.map(Wind.cardinalDirection),
                gustMph: self.current.windGusts
            ),
            source: "Open-Meteo current model"
        )

        let hourlyValues = hourly.values(calendar: calendar)
        let dailyForecasts = daily.values(calendar: calendar, hourly: hourlyValues)

        return WeatherSnapshot(
            current: current,
            daily: dailyForecasts,
            fetchedAt: Date(),
            sourceDescription: "Open-Meteo",
            locationName: nil,
            coordinate: coordinate
        )
    }
}

public struct OpenMeteoCurrent: Decodable {
    public let time: String
    public let temperature: Double
    public let relativeHumidity: Int?
    public let apparentTemperature: Double?
    public let precipitation: Double?
    public let weatherCode: Int
    public let cloudCover: Int?
    public let windSpeed: Double?
    public let windDirection: Int?
    public let windGusts: Double?
    public let isDay: Int?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case relativeHumidity = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitation
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
        case isDay = "is_day"
    }
}

public struct OpenMeteoHourly: Decodable {
    public let time: [String]
    public let temperature: [Double]
    public let apparentTemperature: [Double?]?
    public let precipitationProbability: [Int?]?
    public let weatherCode: [Int]
    public let relativeHumidity: [Int?]?
    public let dewPoint: [Double?]?
    public let uvIndex: [Double?]?
    public let cloudCover: [Int?]?
    public let visibility: [Double?]?
    public let windSpeed: [Double?]?
    public let windDirection: [Int?]?
    public let windGusts: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case relativeHumidity = "relative_humidity_2m"
        case dewPoint = "dew_point_2m"
        case uvIndex = "uv_index"
        case cloudCover = "cloud_cover"
        case visibility
        case windSpeed = "wind_speed_10m"
        case windDirection = "wind_direction_10m"
        case windGusts = "wind_gusts_10m"
    }

    public func values(calendar: Calendar) -> [HourlyForecast] {
        time.indices.compactMap { index in
            guard let date = Self.date(from: time[index], calendar: calendar),
                  temperature.indices.contains(index),
                  weatherCode.indices.contains(index) else { return nil }
            let code = weatherCode[index]
            let direction = windDirection?[safe: index] ?? nil
            let apparent = apparentTemperature?[safe: index] ?? nil
            let dew = dewPoint?[safe: index] ?? nil
            let visibilityFeet = visibility?[safe: index] ?? nil
            return HourlyForecast(
                startTime: date,
                temperatureF: Int(temperature[index].rounded()),
                apparentTemperatureF: apparent.map { Int($0.rounded()) },
                precipitationChance: precipitationProbability?[safe: index] ?? nil,
                uvIndex: uvIndex?[safe: index] ?? nil,
                humidity: relativeHumidity?[safe: index] ?? nil,
                dewPointF: dew.map { Int($0.rounded()) },
                cloudCover: cloudCover?[safe: index] ?? nil,
                visibilityFeet: visibilityFeet.map { Int($0.rounded()) },
                condition: WeatherCondition.fromWMOCode(code),
                summary: WeatherCondition.wmoSummary(code),
                wind: Wind(
                    speedMph: windSpeed?[safe: index] ?? nil,
                    directionDegrees: direction,
                    directionText: direction.map(Wind.cardinalDirection),
                    gustMph: windGusts?[safe: index] ?? nil
                )
            )
        }
    }

    static func date(from text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: text)
    }
}

public struct OpenMeteoDaily: Decodable {
    public let time: [String]
    public let weatherCode: [Int]
    public let temperatureMax: [Double]
    public let temperatureMin: [Double]
    public let apparentTemperatureMax: [Double?]?
    public let apparentTemperatureMin: [Double?]?
    public let precipitationProbabilityMax: [Int?]?
    public let precipitationSum: [Double?]?
    public let sunrise: [String?]?
    public let sunset: [String?]?
    public let uvIndexMax: [Double?]?
    public let windSpeedMax: [Double?]?
    public let windGustsMax: [Double?]?
    public let windDirectionDominant: [Int?]?
    public let daylightDuration: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
        case apparentTemperatureMax = "apparent_temperature_max"
        case apparentTemperatureMin = "apparent_temperature_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case sunrise
        case sunset
        case uvIndexMax = "uv_index_max"
        case windSpeedMax = "wind_speed_10m_max"
        case windGustsMax = "wind_gusts_10m_max"
        case windDirectionDominant = "wind_direction_10m_dominant"
        case daylightDuration = "daylight_duration"
    }

    public func values(calendar: Calendar, hourly: [HourlyForecast]) -> [DailyForecast] {
        let hourlyByDay = Dictionary(grouping: hourly) { calendar.startOfDay(for: $0.startTime) }

        return time.indices.compactMap { index in
            guard let date = Self.day(from: time[index], calendar: calendar),
                  temperatureMax.indices.contains(index),
                  temperatureMin.indices.contains(index),
                  weatherCode.indices.contains(index) else { return nil }
            let code = weatherCode[index]
            let direction = windDirectionDominant?[safe: index] ?? nil
            let apparentHigh = apparentTemperatureMax?[safe: index] ?? nil
            let apparentLow = apparentTemperatureMin?[safe: index] ?? nil
            let sunriseText = sunrise?[safe: index] ?? nil
            let sunsetText = sunset?[safe: index] ?? nil
            return DailyForecast(
                date: date,
                highF: Int(temperatureMax[index].rounded()),
                lowF: Int(temperatureMin[index].rounded()),
                precipitationChance: precipitationProbabilityMax?[safe: index] ?? nil,
                precipitationAmountInches: precipitationSum?[safe: index] ?? nil,
                condition: WeatherCondition.fromWMOCode(code),
                summary: WeatherCondition.wmoSummary(code),
                sunrise: sunriseText.flatMap { OpenMeteoHourly.date(from: $0, calendar: calendar) },
                sunset: sunsetText.flatMap { OpenMeteoHourly.date(from: $0, calendar: calendar) },
                daylightDurationSeconds: daylightDuration?[safe: index] ?? nil,
                uvIndexMax: uvIndexMax?[safe: index] ?? nil,
                apparentHighF: apparentHigh.map { Int($0.rounded()) },
                apparentLowF: apparentLow.map { Int($0.rounded()) },
                wind: Wind(
                    speedMph: windSpeedMax?[safe: index] ?? nil,
                    directionDegrees: direction,
                    directionText: direction.map(Wind.cardinalDirection),
                    gustMph: windGustsMax?[safe: index] ?? nil
                ),
                hourly: hourlyByDay[date] ?? []
            )
        }
    }

    static func day(from text: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text).map { calendar.startOfDay(for: $0) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
