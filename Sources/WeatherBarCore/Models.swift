import Foundation

public struct Coordinate: Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct WeatherSnapshot: Equatable {
    public let current: CurrentWeather
    public let daily: [DailyForecast]
    public let fetchedAt: Date
    public let sourceDescription: String
    public let locationName: String?

    public init(
        current: CurrentWeather,
        daily: [DailyForecast],
        fetchedAt: Date,
        sourceDescription: String,
        locationName: String?
    ) {
        self.current = current
        self.daily = daily
        self.fetchedAt = fetchedAt
        self.sourceDescription = sourceDescription
        self.locationName = locationName
    }
}

public struct CurrentWeather: Equatable {
    public let temperatureF: Int
    public let condition: WeatherCondition
    public let summary: String
    public let precipitationChance: Int?

    public init(temperatureF: Int, condition: WeatherCondition, summary: String, precipitationChance: Int?) {
        self.temperatureF = temperatureF
        self.condition = condition
        self.summary = summary
        self.precipitationChance = precipitationChance
    }
}

public struct DailyForecast: Equatable, Identifiable {
    public let id: Date
    public let date: Date
    public let highF: Int
    public let lowF: Int
    public let precipitationChance: Int?
    public let condition: WeatherCondition
    public let summary: String
    public let hourly: [HourlyForecast]

    public init(
        date: Date,
        highF: Int,
        lowF: Int,
        precipitationChance: Int?,
        condition: WeatherCondition,
        summary: String,
        hourly: [HourlyForecast]
    ) {
        self.id = date
        self.date = date
        self.highF = highF
        self.lowF = lowF
        self.precipitationChance = precipitationChance
        self.condition = condition
        self.summary = summary
        self.hourly = hourly
    }
}

public struct HourlyForecast: Equatable, Identifiable {
    public let id: Date
    public let startTime: Date
    public let temperatureF: Int
    public let precipitationChance: Int?
    public let condition: WeatherCondition
    public let summary: String
    public let wind: String

    public init(
        startTime: Date,
        temperatureF: Int,
        precipitationChance: Int?,
        condition: WeatherCondition,
        summary: String,
        wind: String
    ) {
        self.id = startTime
        self.startTime = startTime
        self.temperatureF = temperatureF
        self.precipitationChance = precipitationChance
        self.condition = condition
        self.summary = summary
        self.wind = wind
    }
}

public enum WeatherCondition: String, Equatable {
    case sunny
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case thunderstorm
    case snow
    case sleet
    case wind
    case unknown

    public var symbolName: String {
        switch self {
        case .sunny:
            return "sun.max.fill"
        case .partlyCloudy:
            return "cloud.sun.fill"
        case .cloudy:
            return "cloud.fill"
        case .fog:
            return "cloud.fog.fill"
        case .rain:
            return "cloud.rain.fill"
        case .thunderstorm:
            return "cloud.bolt.rain.fill"
        case .snow:
            return "cloud.snow.fill"
        case .sleet:
            return "cloud.sleet.fill"
        case .wind:
            return "wind"
        case .unknown:
            return "questionmark.circle"
        }
    }

    public static func classify(_ summary: String) -> WeatherCondition {
        let text = summary.lowercased()
        if text.contains("thunder") || text.contains("lightning") {
            return .thunderstorm
        }
        if text.contains("snow") || text.contains("blizzard") {
            return .snow
        }
        if text.contains("sleet") || text.contains("freezing rain") || text.contains("ice") {
            return .sleet
        }
        if text.contains("rain") || text.contains("showers") || text.contains("drizzle") {
            return .rain
        }
        if text.contains("fog") || text.contains("haze") || text.contains("smoke") {
            return .fog
        }
        if text.contains("wind") || text.contains("breezy") {
            return .wind
        }
        if text.contains("partly") || text.contains("mostly sunny") || text.contains("mostly clear") {
            return .partlyCloudy
        }
        if text.contains("cloud") || text.contains("overcast") {
            return .cloudy
        }
        if text.contains("sun") || text.contains("clear") || text.contains("fair") {
            return .sunny
        }
        return .unknown
    }
}
