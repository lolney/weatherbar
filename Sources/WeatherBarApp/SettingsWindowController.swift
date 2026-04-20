import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, onSave: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeatherBar Settings"
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: WeatherSettingsView(
            settings: settings,
            onSave: { [weak self] in
                onSave()
                self?.close()
            }
        ))
        window.center()
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct WeatherSettingsView: View {
    private let settings: AppSettings
    private let onSave: () -> Void

    @State private var locationMode: LocationMode
    @State private var providerMode: ProviderMode
    @State private var manualLocationName: String
    @State private var manualLatitude: Double
    @State private var manualLongitude: Double

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        _locationMode = State(initialValue: settings.locationMode)
        _providerMode = State(initialValue: settings.providerMode)
        _manualLocationName = State(initialValue: settings.manualLocationName)
        _manualLatitude = State(initialValue: settings.manualLatitude)
        _manualLongitude = State(initialValue: settings.manualLongitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                settingRow("Location") {
                    Picker("Location", selection: $locationMode) {
                        ForEach(LocationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                settingRow("Provider") {
                    Picker("Provider", selection: $providerMode) {
                        ForEach(ProviderMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                settingRow("Manual Name") {
                    TextField("Manual Location", text: $manualLocationName)
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("Latitude") {
                    TextField("Latitude", value: $manualLatitude, format: .number.precision(.fractionLength(4)))
                        .textFieldStyle(.roundedBorder)
                }

                settingRow("Longitude") {
                    TextField("Longitude", value: $manualLongitude, format: .number.precision(.fractionLength(4)))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Save", action: save)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: WeatherPalette.teal))
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(width: 420, height: 260)
        .background(.ultraThinMaterial)
        .overlay {
            Color(nsColor: WeatherPalette.glassOverlay)
                .allowsHitTesting(false)
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .frame(width: 110, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        settings.locationMode = locationMode
        settings.providerMode = providerMode
        settings.manualLocationName = manualLocationName.isEmpty ? "Manual Location" : manualLocationName
        settings.manualLatitude = manualLatitude
        settings.manualLongitude = manualLongitude
        onSave()
    }
}
