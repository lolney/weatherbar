import AppKit
import SwiftUI
import WeatherBarCore

@MainActor
final class WeatherPopoverState: ObservableObject {
    @Published var snapshot: WeatherSnapshot?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var savedLocations: [SavedLocation] = []
    @Published var selectedLocationID = AppSettings.currentLocationID
}

@MainActor
final class WeatherPopoverViewController: NSHostingController<WeatherPopoverView> {
    static let preferredSize = NSSize(width: 760, height: 600)

    private let popoverState: WeatherPopoverState

    init(
        onRefresh: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onSelectLocation: @escaping (String) -> Void,
        onAddLocation: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        let state = WeatherPopoverState()
        self.popoverState = state
        super.init(rootView: WeatherPopoverView(
            state: state,
            onRefresh: onRefresh,
            onSettings: onSettings,
            onSelectLocation: onSelectLocation,
            onAddLocation: onAddLocation,
            onQuit: onQuit
        ))
        preferredContentSize = Self.preferredSize
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(
        snapshot: WeatherSnapshot?,
        isLoading: Bool,
        error: Error?,
        savedLocations: [SavedLocation],
        selectedLocationID: String
    ) {
        preferredContentSize = Self.preferredSize
        view.setFrameSize(Self.preferredSize)
        popoverState.snapshot = snapshot
        popoverState.isLoading = isLoading
        popoverState.error = error
        popoverState.savedLocations = savedLocations
        popoverState.selectedLocationID = selectedLocationID
    }
}
