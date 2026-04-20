import Foundation

public protocol WeatherProvider {
    func fetchWeather(for coordinate: Coordinate) async throws -> WeatherSnapshot
}

public protocol LocationProviding {
    func currentLocation() async throws -> LocationFix
}

public extension LocationProviding {
    func currentCoordinate() async throws -> Coordinate {
        try await currentLocation().coordinate
    }
}

public enum WeatherError: Error, Equatable, LocalizedError {
    case invalidResponse
    case unsupportedLocation(String)
    case locationUnavailable(String)
    case noForecast

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The weather service returned an invalid response."
        case .unsupportedLocation(let message):
            return message
        case .locationUnavailable(let message):
            return message
        case .noForecast:
            return "No forecast data is available."
        }
    }
}

public protocol HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.invalidResponse
        }
        return (data, httpResponse)
    }
}
