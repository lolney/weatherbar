import AppKit

final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let onSave: () -> Void
    private let locationPopup = NSPopUpButton()
    private let providerPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let latField = NSTextField()
    private let lonField = NSTextField()

    init(settings: AppSettings, onSave: @escaping () -> Void) {
        self.settings = settings
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WeatherBar Settings"
        super.init(window: window)
        buildUI()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        locationPopup.addItems(withTitles: ["Use Current Location", "Manual Location"])
        providerPopup.addItems(withTitles: ["NWS + Open-Meteo Details", "Open-Meteo Only"])

        stack.addArrangedSubview(row("Location", locationPopup))
        stack.addArrangedSubview(row("Provider", providerPopup))
        stack.addArrangedSubview(row("Manual Name", nameField))
        stack.addArrangedSubview(row("Latitude", latField))
        stack.addArrangedSubview(row("Longitude", lonField))
        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.addArrangedSubview(NSView())
        actions.addArrangedSubview(NSButton(title: "Save", target: self, action: #selector(save)))
        stack.addArrangedSubview(actions)
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        return row
    }

    private func loadValues() {
        locationPopup.selectItem(at: settings.locationMode == .current ? 0 : 1)
        providerPopup.selectItem(at: settings.providerMode == .nwsWithOpenMeteo ? 0 : 1)
        nameField.stringValue = settings.manualLocationName
        latField.stringValue = "\(settings.manualLatitude)"
        lonField.stringValue = "\(settings.manualLongitude)"
    }

    @objc private func save() {
        settings.locationMode = locationPopup.indexOfSelectedItem == 0 ? .current : .manual
        settings.providerMode = providerPopup.indexOfSelectedItem == 0 ? .nwsWithOpenMeteo : .openMeteoOnly
        settings.manualLocationName = nameField.stringValue.isEmpty ? "Manual Location" : nameField.stringValue
        if let lat = Double(latField.stringValue) {
            settings.manualLatitude = lat
        }
        if let lon = Double(lonField.stringValue) {
            settings.manualLongitude = lon
        }
        onSave()
        close()
    }
}
