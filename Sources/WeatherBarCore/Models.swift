import Foundation

public struct Coordinate: Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct LocationFix: Equatable {
    public let coordinate: Coordinate
    public let horizontalAccuracyMeters: Double?
    public let displayName: String?
    public let resolvedAt: Date

    public init(
        coordinate: Coordinate,
        horizontalAccuracyMeters: Double?,
        displayName: String?,
        resolvedAt: Date
    ) {
        self.coordinate = coordinate
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.displayName = displayName
        self.resolvedAt = resolvedAt
    }
}

public struct WeatherSnapshot: Equatable {
    public let current: CurrentWeather
    public let daily: [DailyForecast]
    public let fetchedAt: Date
    public let sourceDescription: String
    public let locationName: String?
    public let coordinate: Coordinate?
    public let locationAccuracyMeters: Double?

    public init(
        current: CurrentWeather,
        daily: [DailyForecast],
        fetchedAt: Date,
        sourceDescription: String,
        locationName: String?,
        coordinate: Coordinate? = nil,
        locationAccuracyMeters: Double? = nil
    ) {
        self.current = current
        self.daily = daily
        self.fetchedAt = fetchedAt
        self.sourceDescription = sourceDescription
        self.locationName = locationName
        self.coordinate = coordinate
        self.locationAccuracyMeters = locationAccuracyMeters
    }

    public func withLocation(_ location: LocationFix) -> WeatherSnapshot {
        WeatherSnapshot(
            current: current,
            daily: daily,
            fetchedAt: fetchedAt,
            sourceDescription: sourceDescription,
            locationName: location.displayName ?? locationName,
            coordinate: location.coordinate,
            locationAccuracyMeters: location.horizontalAccuracyMeters
        )
    }
}

public struct CurrentWeather: Equatable {
    public let temperatureF: Int
    public let apparentTemperatureF: Int?
    public let condition: WeatherCondition
    public let summary: String
    public let precipitationChance: Int?
    public let humidity: Int?
    public let dewPointF: Int?
    public let cloudCover: Int?
    public let wind: Wind?
    public let observationStation: ObservationStation?
    public let observedAt: Date?
    public let source: String

    public init(
        temperatureF: Int,
        apparentTemperatureF: Int? = nil,
        condition: WeatherCondition,
        summary: String,
        precipitationChance: Int?,
        humidity: Int? = nil,
        dewPointF: Int? = nil,
        cloudCover: Int? = nil,
        wind: Wind? = nil,
        observationStation: ObservationStation? = nil,
        observedAt: Date? = nil,
        source: String = "Forecast"
    ) {
        self.temperatureF = temperatureF
        self.apparentTemperatureF = apparentTemperatureF
        self.condition = condition
        self.summary = summary
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.dewPointF = dewPointF
        self.cloudCover = cloudCover
        self.wind = wind
        self.observationStation = observationStation
        self.observedAt = observedAt
        self.source = source
    }
}

public struct DailyForecast: Equatable, Identifiable {
    public let id: Date
    public let date: Date
    public let highF: Int
    public let lowF: Int
    public let precipitationChance: Int?
    public let precipitationAmountInches: Double?
    public let condition: WeatherCondition
    public let summary: String
    public let sunrise: Date?
    public let sunset: Date?
    public let daylightDurationSeconds: Double?
    public let uvIndexMax: Double?
    public let apparentHighF: Int?
    public let apparentLowF: Int?
    public let wind: Wind?
    public let hourly: [HourlyForecast]

    public init(
        date: Date,
        highF: Int,
        lowF: Int,
        precipitationChance: Int?,
        precipitationAmountInches: Double? = nil,
        condition: WeatherCondition,
        summary: String,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        daylightDurationSeconds: Double? = nil,
        uvIndexMax: Double? = nil,
        apparentHighF: Int? = nil,
        apparentLowF: Int? = nil,
        wind: Wind? = nil,
        hourly: [HourlyForecast]
    ) {
        self.id = date
        self.date = date
        self.highF = highF
        self.lowF = lowF
        self.precipitationChance = precipitationChance
        self.precipitationAmountInches = precipitationAmountInches
        self.condition = condition
        self.summary = summary
        self.sunrise = sunrise
        self.sunset = sunset
        self.daylightDurationSeconds = daylightDurationSeconds
        self.uvIndexMax = uvIndexMax
        self.apparentHighF = apparentHighF
        self.apparentLowF = apparentLowF
        self.wind = wind
        self.hourly = hourly
    }
}

public struct HourlyForecast: Equatable, Identifiable {
    public let id: Date
    public let startTime: Date
    public let temperatureF: Int
    public let apparentTemperatureF: Int?
    public let precipitationChance: Int?
    public let uvIndex: Double?
    public let humidity: Int?
    public let dewPointF: Int?
    public let cloudCover: Int?
    public let visibilityFeet: Int?
    public let condition: WeatherCondition
    public let summary: String
    public let wind: Wind?

    public init(
        startTime: Date,
        temperatureF: Int,
        apparentTemperatureF: Int? = nil,
        precipitationChance: Int?,
        uvIndex: Double? = nil,
        humidity: Int? = nil,
        dewPointF: Int? = nil,
        cloudCover: Int? = nil,
        visibilityFeet: Int? = nil,
        condition: WeatherCondition,
        summary: String,
        wind: Wind? = nil
    ) {
        self.id = startTime
        self.startTime = startTime
        self.temperatureF = temperatureF
        self.apparentTemperatureF = apparentTemperatureF
        self.precipitationChance = precipitationChance
        self.uvIndex = uvIndex
        self.humidity = humidity
        self.dewPointF = dewPointF
        self.cloudCover = cloudCover
        self.visibilityFeet = visibilityFeet
        self.condition = condition
        self.summary = summary
        self.wind = wind
    }
}

public struct Wind: Equatable {
    public let speedMph: Double?
    public let directionDegrees: Int?
    public let directionText: String?
    public let gustMph: Double?

    public init(speedMph: Double?, directionDegrees: Int?, directionText: String?, gustMph: Double? = nil) {
        self.speedMph = speedMph
        self.directionDegrees = directionDegrees
        self.directionText = directionText
        self.gustMph = gustMph
    }

    public var displayText: String {
        let speed = speedMph.map { "\(Int($0.rounded())) mph" } ?? "Wind"
        let direction = directionText ?? directionDegrees.map(Self.cardinalDirection)
        let gust = gustMph.map { " gust \(Int($0.rounded()))" } ?? ""
        return [speed, direction].compactMap { $0 }.joined(separator: " ") + gust
    }

    public static func cardinalDirection(_ degrees: Int) -> String {
        let normalized = ((degrees % 360) + 360) % 360
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((Double(normalized) / 22.5).rounded()) % directions.count
        return directions[index]
    }
}

public struct ObservationStation: Equatable {
    public let identifier: String
    public let name: String
    public let distanceMiles: Double?

    public init(identifier: String, name: String, distanceMiles: Double?) {
        self.identifier = identifier
        self.name = name
        self.distanceMiles = distanceMiles
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

    public static func fromWMOCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0, 1:
            return .sunny
        case 2:
            return .partlyCloudy
        case 3:
            return .cloudy
        case 45, 48:
            return .fog
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return .rain
        case 71, 73, 75, 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .thunderstorm
        default:
            return .unknown
        }
    }

    public static func wmoSummary(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Sunny"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms with Hail"
        default: return "Unknown"
        }
    }
}
