// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WeatherBar",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(name: "WeatherBarCore", targets: ["WeatherBarCore"]),
        .executable(name: "WeatherBarApp", targets: ["WeatherBarApp"])
    ],
    targets: [
        .target(name: "WeatherBarCore"),
        .executableTarget(
            name: "WeatherBarApp",
            dependencies: ["WeatherBarCore"]
        ),
        .testTarget(
            name: "WeatherBarCoreTests",
            dependencies: ["WeatherBarCore"]
        )
    ]
)
