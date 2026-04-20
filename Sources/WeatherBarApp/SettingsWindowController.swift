import AppKit
import MapKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, onSave: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
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
    private let launchAtLogin = LaunchAtLoginController.shared
    private let onSave: () -> Void

    @State private var providerMode: ProviderMode
    @State private var selectedLocationID: String
    @State private var editingLocationID: String?
    @State private var savedLocations: [SavedLocation]
    @State private var startsAtLogin: Bool
    @State private var launchAtLoginStatus: String
    @State private var launchAtLoginError: String?

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        _providerMode = State(initialValue: settings.providerMode)
        _selectedLocationID = State(initialValue: settings.selectedLocationID)
        _savedLocations = State(initialValue: settings.savedLocations)
        _editingLocationID = State(initialValue: settings.savedLocations.first?.id)
        _startsAtLogin = State(initialValue: LaunchAtLoginController.shared.isEnabled)
        _launchAtLoginStatus = State(initialValue: LaunchAtLoginController.shared.statusText)
        _launchAtLoginError = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                settingRow("Provider") {
                    Picker("Provider", selection: $providerMode) {
                        ForEach(ProviderMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                settingRow("Active Location") {
                    Picker("Active Location", selection: $selectedLocationID) {
                        Text("Current Location").tag(AppSettings.currentLocationID)
                        ForEach(savedLocations) { location in
                            Text(location.name).tag(location.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                settingRow("Startup") {
                    Toggle("Launch WeatherBar when you log in", isOn: $startsAtLogin)
                        .toggleStyle(.checkbox)
                }
            }

            Text(launchAtLoginError ?? launchAtLoginStatus)
                .font(.caption)
                .foregroundStyle(launchAtLoginError == nil ? Color(nsColor: WeatherPalette.secondaryInk) : .red)
                .lineLimit(2)

            Divider()

            locationEditor

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
        .frame(width: 720, height: 560)
        .background(.ultraThinMaterial)
        .overlay {
            Color(nsColor: WeatherPalette.glassOverlay)
                .allowsHitTesting(false)
        }
    }

    private var locationEditor: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Locations")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: WeatherPalette.ink))

                List(selection: $editingLocationID) {
                    ForEach(savedLocations) { location in
                        Text(location.name)
                            .tag(Optional(location.id))
                    }
                }
                .frame(width: 190, height: 300)

                HStack(spacing: 8) {
                    Button("Add", action: addLocation)
                    Button("Delete", action: deleteSelectedLocation)
                        .disabled(editingLocationID == nil)
                }
                .controlSize(.small)
            }

            if let binding = selectedLocationBinding {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Location Name", text: binding.name)
                        .textFieldStyle(.roundedBorder)

                    LocationMapPicker(coordinate: binding.coordinate)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(nsColor: WeatherPalette.panelStroke), lineWidth: 1)
                        }
                        .frame(height: 210)

                    HStack(spacing: 8) {
                        TextField("Latitude", value: binding.latitude, format: .number.precision(.fractionLength(5)))
                            .textFieldStyle(.roundedBorder)
                        TextField("Longitude", value: binding.longitude, format: .number.precision(.fractionLength(5)))
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Click the map to move the saved location pin.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a saved location to edit it on the map.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    private var selectedLocationBinding: LocationBinding? {
        guard let editingLocationID,
              let index = savedLocations.firstIndex(where: { $0.id == editingLocationID }) else {
            return nil
        }
        return LocationBinding(
            name: Binding(
                get: { savedLocations[index].name },
                set: { savedLocations[index].name = $0 }
            ),
            latitude: Binding(
                get: { savedLocations[index].latitude },
                set: { savedLocations[index].latitude = $0 }
            ),
            longitude: Binding(
                get: { savedLocations[index].longitude },
                set: { savedLocations[index].longitude = $0 }
            ),
            coordinate: Binding(
                get: {
                    CLLocationCoordinate2D(
                        latitude: savedLocations[index].latitude,
                        longitude: savedLocations[index].longitude
                    )
                },
                set: { coordinate in
                    savedLocations[index].latitude = coordinate.latitude
                    savedLocations[index].longitude = coordinate.longitude
                }
            )
        )
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

    private func addLocation() {
        let location = SavedLocation(
            id: UUID().uuidString,
            name: "New Location",
            latitude: 37.7651,
            longitude: -122.4497
        )
        savedLocations.append(location)
        editingLocationID = location.id
        selectedLocationID = location.id
    }

    private func deleteSelectedLocation() {
        guard let editingLocationID,
              let index = savedLocations.firstIndex(where: { $0.id == editingLocationID }) else {
            return
        }
        savedLocations.remove(at: index)
        if selectedLocationID == editingLocationID {
            selectedLocationID = AppSettings.currentLocationID
        }
        self.editingLocationID = savedLocations.first?.id
    }

    private func save() {
        do {
            try launchAtLogin.setEnabled(startsAtLogin)
            launchAtLoginStatus = launchAtLogin.statusText
            launchAtLoginError = nil

            settings.providerMode = providerMode
            settings.savedLocations = savedLocations
            settings.selectedLocationID = normalizedSelectedLocationID
            onSave()
        } catch {
            launchAtLoginStatus = launchAtLogin.statusText
            launchAtLoginError = error.localizedDescription
        }
    }

    private var normalizedSelectedLocationID: String {
        if selectedLocationID == AppSettings.currentLocationID {
            return selectedLocationID
        }
        return savedLocations.contains(where: { $0.id == selectedLocationID }) ? selectedLocationID : AppSettings.currentLocationID
    }

    private struct LocationBinding {
        let name: Binding<String>
        let latitude: Binding<Double>
        let longitude: Binding<Double>
        let coordinate: Binding<CLLocationCoordinate2D>
    }
}
