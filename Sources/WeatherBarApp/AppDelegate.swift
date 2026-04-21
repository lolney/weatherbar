import AppKit
import Foundation
import WeatherBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private struct RepositoryKey: Hashable {
        let providerMode: ProviderMode
        let locationID: String
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = AppSettings.shared
    private let popover = NSPopover()
    private var popoverController: WeatherPopoverViewController!
    private var settingsWindowController: SettingsWindowController?
    private var repository: WeatherRepository!
    private var activeRepositoryKey: RepositoryKey?
    private var repositories: [RepositoryKey: WeatherRepository] = [:]
    private var snapshotCache: [RepositoryKey: WeatherSnapshot] = [:]
    private var localPopoverMonitor: Any?
    private var globalPopoverMonitor: Any?
    private var snapshot: WeatherSnapshot?
    private var lastError: Error?
    private var isLoading = false
    private var refreshTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var refreshGeneration = 0

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

    private func configureRepository(resetCaches: Bool = false) {
        if resetCaches {
            repositories.removeAll()
            snapshotCache.removeAll()
        }

        let key = RepositoryKey(
            providerMode: settings.providerMode,
            locationID: settings.selectedLocationID
        )
        activeRepositoryKey = key

        if let cachedRepository = repositories[key] {
            repository = cachedRepository
            snapshot = snapshotCache[key]
            return
        }

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
        repositories[key] = repository
        snapshot = snapshotCache[key]
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        updateStatusButton()
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.delegate = self
        popover.animates = true
        popover.contentSize = WeatherPopoverViewController.preferredSize
        popoverController = WeatherPopoverViewController(
            onRefresh: { [weak self] in self?.refresh(force: true) },
            onSettings: { [weak self] in self?.showSettings() },
            onSelectLocation: { [weak self] locationID in self?.selectLocation(locationID) },
            onAddLocation: { [weak self] in self?.showSettings() },
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
            installPopoverEventMonitors()
        }
    }

    private func showSettings() {
        closePopover()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onSave: { [weak self] in
                    self?.reloadSettingsAndRefresh()
                }
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        settingsWindowController?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func selectLocation(_ locationID: String) {
        guard settings.selectedLocationID != locationID else { return }
        settings.selectedLocationID = locationID
        refreshGeneration += 1
        refreshTask?.cancel()
        retryTask?.cancel()
        isLoading = false
        consecutiveFailures = 0
        lastError = nil
        configureRepository()
        updateStatusButton()
        rebuildPopover()
        refresh(force: false)
    }

    private func reloadSettingsAndRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        retryTask?.cancel()
        isLoading = false
        consecutiveFailures = 0
        lastError = nil
        configureRepository(resetCaches: true)
        updateStatusButton()
        rebuildPopover()
        refresh(force: true)
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
        guard let repository else { return }
        isLoading = true
        let generation = refreshGeneration
        let repositoryKey = activeRepositoryKey
        rebuildPopover()

        refreshTask?.cancel()
        refreshTask = Task { [weak self, generation, repository, repositoryKey] in
            guard let self else { return }
            do {
                let fresh = try await repository.refresh(force: force)
                await MainActor.run {
                    if let repositoryKey, self.repositories[repositoryKey] === repository {
                        self.snapshotCache[repositoryKey] = fresh
                    }
                    guard generation == self.refreshGeneration else { return }
                    self.snapshot = fresh
                    self.lastError = nil
                    self.consecutiveFailures = 0
                    self.isLoading = false
                    self.updateStatusButton()
                    self.rebuildPopover()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.refreshGeneration else { return }
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

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverEventMonitors()
    }

    private func installPopoverEventMonitors() {
        removePopoverEventMonitors()

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        localPopoverMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closePopover()
                return nil
            }
            if self.shouldClosePopover(for: event) {
                self.closePopover()
            }
            return event
        }

        globalPopoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return }
            let screenPoint = NSEvent.mouseLocation
            if !self.pointIsInsidePopover(screenPoint) && !self.pointIsInsideStatusItem(screenPoint) {
                self.closePopover()
            }
        }
    }

    private func removePopoverEventMonitors() {
        if let localPopoverMonitor {
            NSEvent.removeMonitor(localPopoverMonitor)
            self.localPopoverMonitor = nil
        }
        if let globalPopoverMonitor {
            NSEvent.removeMonitor(globalPopoverMonitor)
            self.globalPopoverMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        guard event.type != .keyDown else { return false }

        if let window = event.window {
            if window === popover.contentViewController?.view.window {
                return false
            }
            if window === statusItem.button?.window {
                return false
            }
            let className = NSStringFromClass(type(of: window))
            if className.localizedCaseInsensitiveContains("Menu") {
                return false
            }
        }

        let screenPoint: NSPoint
        if let window = event.window {
            screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = NSEvent.mouseLocation
        }
        return !pointIsInsidePopover(screenPoint) && !pointIsInsideStatusItem(screenPoint)
    }

    private func pointIsInsidePopover(_ point: NSPoint) -> Bool {
        guard let windowFrame = popover.contentViewController?.view.window?.frame else {
            return false
        }
        return windowFrame.contains(point)
    }

    private func pointIsInsideStatusItem(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            return false
        }
        let frameInWindow = button.convert(button.bounds, to: nil)
        let screenFrame = buttonWindow.convertToScreen(frameInWindow)
        return screenFrame.contains(point)
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
        popoverController.render(
            snapshot: snapshot,
            isLoading: isLoading,
            error: lastError,
            savedLocations: settings.savedLocations,
            selectedLocationID: settings.selectedLocationID
        )
    }
}
