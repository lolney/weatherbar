import AppKit
import Foundation
import WeatherBarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let renderer = MenuRenderer()
    private var repository: WeatherRepository!
    private var snapshot: WeatherSnapshot?
    private var lastError: Error?
    private var isLoading = false
    private var refreshTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        repository = WeatherRepository(
            provider: NWSWeatherProvider(),
            locationProvider: LocationService()
        )

        if let button = statusItem.button {
            renderer.updateStatusButton(button, snapshot: nil)
        }

        statusItem.menu = renderer.menu(
            snapshot: nil,
            isLoading: true,
            error: nil,
            onRefresh: { [weak self] in self?.refresh(force: true) },
            onQuit: { NSApp.terminate(nil) }
        )
        statusItem.menu?.delegate = self

        refresh(force: true)
        startBackgroundRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel()
        backgroundTask?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh(force: false)
    }

    private func startBackgroundRefresh() {
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)
                guard let self else { return }
                await MainActor.run {
                    self.refresh(force: true)
                }
            }
        }
    }

    private func refresh(force: Bool) {
        guard !isLoading else { return }
        isLoading = true
        rebuildMenu()

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await repository.refresh(force: force)
                await MainActor.run {
                    self.snapshot = fresh
                    self.lastError = nil
                    self.isLoading = false
                    self.rebuildMenu()
                }
            } catch {
                await MainActor.run {
                    self.lastError = error
                    self.isLoading = false
                    self.rebuildMenu()
                }
            }
        }
    }

    private func rebuildMenu() {
        if let button = statusItem.button {
            renderer.updateStatusButton(button, snapshot: snapshot)
        }

        let menu = renderer.menu(
            snapshot: snapshot,
            isLoading: isLoading,
            error: lastError,
            onRefresh: { [weak self] in self?.refresh(force: true) },
            onQuit: { NSApp.terminate(nil) }
        )
        menu.delegate = self
        statusItem.menu = menu
    }
}
