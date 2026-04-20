import Foundation

@MainActor
final class LaunchAtLoginController {
    static let shared = LaunchAtLoginController()

    var isEnabled: Bool {
        launchAgentBundlePath == currentBundlePath
    }

    var statusText: String {
        guard let launchAgentBundlePath else {
            return "Launch at login is off."
        }

        if launchAgentBundlePath == currentBundlePath {
            return "Launch at login is enabled."
        }

        return "Launch at login points to a different WeatherBar build."
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try writeLaunchAgent()
        } else if fileManager.fileExists(atPath: launchAgentURL.path) {
            try fileManager.removeItem(at: launchAgentURL)
        }
    }

    private let fileManager = FileManager.default
    private let label = "local.weatherbar.login"

    private var launchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private var currentBundlePath: String {
        Bundle.main.bundleURL.path
    }

    private var launchAgentBundlePath: String? {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String],
              arguments.count >= 2 else {
            return nil
        }
        return arguments[1]
    }

    private func writeLaunchAgent() throws {
        let directory = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                currentBundlePath
            ],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
    }
}
