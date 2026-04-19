import AppKit
import Foundation
import WeatherBarCore

final class MenuRenderer {
    private let dayFormatter: DateFormatter
    private let hourFormatter: DateFormatter

    init() {
        dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE MMM d"

        hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "ha"
    }

    func updateStatusButton(_ button: NSStatusBarButton, snapshot: WeatherSnapshot?) {
        guard let snapshot else {
            button.title = "--°"
            button.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Weather")
            return
        }

        button.title = " \(snapshot.current.temperatureF)°"
        button.image = NSImage(
            systemSymbolName: snapshot.current.condition.symbolName,
            accessibilityDescription: snapshot.current.summary
        )
        button.imagePosition = .imageLeft
        button.toolTip = "\(snapshot.current.summary), \(snapshot.current.temperatureF)°F"
    }

    func menu(
        snapshot: WeatherSnapshot?,
        isLoading: Bool,
        error: Error?,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()

        if isLoading {
            let item = NSMenuItem(title: "Refreshing...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        if let error {
            let item = NSMenuItem(title: "Error: \(error.localizedDescription)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if let snapshot {
            let current = NSMenuItem(
                title: currentTitle(snapshot),
                action: nil,
                keyEquivalent: ""
            )
            current.isEnabled = false
            menu.addItem(current)

            if let location = snapshot.locationName {
                let locationItem = NSMenuItem(title: location, action: nil, keyEquivalent: "")
                locationItem.isEnabled = false
                menu.addItem(locationItem)
            }

            menu.addItem(.separator())

            for day in snapshot.daily {
                let dayItem = NSMenuItem(title: dayTitle(day), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for hour in day.hourly.prefix(24) {
                    let item = NSMenuItem(title: hourlyTitle(hour), action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    submenu.addItem(item)
                }
                dayItem.submenu = submenu
                menu.addItem(dayItem)
            }

            menu.addItem(.separator())
            let fetched = DateFormatter.localizedString(from: snapshot.fetchedAt, dateStyle: .none, timeStyle: .short)
            let source = NSMenuItem(title: "\(snapshot.sourceDescription) • Updated \(fetched)", action: nil, keyEquivalent: "")
            source.isEnabled = false
            menu.addItem(source)
        } else if error == nil {
            let empty = NSMenuItem(title: "Weather will appear after the first refresh.", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Refresh Now", actionHandler: onRefresh))
        menu.addItem(ActionMenuItem(title: "Quit WeatherBar", actionHandler: onQuit))
        return menu
    }

    private func currentTitle(_ snapshot: WeatherSnapshot) -> String {
        let precip = snapshot.current.precipitationChance.map { " • \($0)% precip" } ?? ""
        return "\(snapshot.current.temperatureF)°F • \(snapshot.current.summary)\(precip)"
    }

    private func dayTitle(_ day: DailyForecast) -> String {
        let precip = day.precipitationChance.map { " • \($0)%" } ?? ""
        return "\(dayFormatter.string(from: day.date)): \(day.lowF)°/\(day.highF)° • \(day.summary)\(precip)"
    }

    private func hourlyTitle(_ hour: HourlyForecast) -> String {
        let precip = hour.precipitationChance.map { " • \($0)% precip" } ?? ""
        return "\(hourFormatter.string(from: hour.startTime)): \(hour.temperatureF)° • \(hour.summary)\(precip) • \(hour.wind)"
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(title: title, action: #selector(runAction), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }
}
