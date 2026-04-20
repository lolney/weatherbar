import AppKit
import Foundation
import WeatherBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = AppSettings.shared
    private let popover = NSPopover()
    private var popoverController: WeatherPopoverViewController!
    private var settingsWindowController: SettingsWindowController?
    private var repository: WeatherRepository!
    private var snapshot: WeatherSnapshot?
    private var lastError: Error?
    private var isLoading = false
    private var refreshTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureRepository()
        configureStatusItem()
        configurePopover()
        refresh(force: true)
        startBackgroundRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        backgroundTask?.cancel()
        retryTask?.cancel()
    }

    private func configureRepository() {
        let primary: WeatherProvider
        switch settings.providerMode {
        case .nwsWithOpenMeteo:
            primary = CompositeWeatherProvider(
                primary: NWSWeatherProvider(),
                supplement: OpenMeteoWeatherProvider()
            )
        case .openMeteoOnly:
            primary = OpenMeteoWeatherProvider()
        }

        repository = WeatherRepository(
            provider: primary,
            locationProvider: SettingsLocationProvider(
                settings: settings,
                currentProvider: LocationService()
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        updateStatusButton()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = WeatherPopoverViewController.preferredSize
        popoverController = WeatherPopoverViewController(
            onRefresh: { [weak self] in self?.refresh(force: true) },
            onSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        popover.contentViewController = popoverController
        rebuildPopover()
    }

    @objc private func togglePopover() {
        refresh(force: false)
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            rebuildPopover()
            popover.contentSize = WeatherPopoverViewController.preferredSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onSave: { [weak self] in
                    self?.configureRepository()
                    self?.snapshot = nil
                    self?.refresh(force: true)
                }
            )
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startBackgroundRefresh() {
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.refresh(force: true)
                }
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = min(pow(2.0, Double(consecutiveFailures)) * 60, 30 * 60)
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.refresh(force: true)
            }
        }
    }

    private func refresh(force: Bool) {
        guard !isLoading else { return }
        isLoading = true
        rebuildPopover()

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await repository.refresh(force: force)
                await MainActor.run {
                    self.snapshot = fresh
                    self.lastError = nil
                    self.consecutiveFailures = 0
                    self.isLoading = false
                    self.updateStatusButton()
                    self.rebuildPopover()
                }
            } catch {
                await MainActor.run {
                    self.lastError = error
                    self.consecutiveFailures += 1
                    self.isLoading = false
                    self.updateStatusButton()
                    self.rebuildPopover()
                    self.scheduleRetry()
                }
            }
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        guard let snapshot else {
            button.title = " --°"
            button.image = NSImage(systemSymbolName: "cloud", accessibilityDescription: "Weather")
            button.imagePosition = .imageLeft
            button.toolTip = lastError?.localizedDescription ?? "WeatherBar"
            return
        }

        button.title = " \(snapshot.current.temperatureF)°"
        button.image = NSImage(
            systemSymbolName: snapshot.current.condition.symbolName,
            accessibilityDescription: snapshot.current.summary
        )
        button.imagePosition = .imageLeft
        button.toolTip = "\(snapshot.current.temperatureF)°F • \(snapshot.current.summary)"
    }

    private func rebuildPopover() {
        popover.contentSize = WeatherPopoverViewController.preferredSize
        popoverController.render(snapshot: snapshot, isLoading: isLoading, error: lastError)
    }
}
