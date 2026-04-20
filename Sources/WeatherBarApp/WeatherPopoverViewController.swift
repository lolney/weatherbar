import AppKit
import WeatherBarCore

final class WeatherPopoverViewController: NSViewController {
    static let preferredSize = NSSize(width: 620, height: 520)

    private let onRefresh: () -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private let stack = NSStackView()
    private let detailStack = NSStackView()
    private var snapshot: WeatherSnapshot?

    init(onRefresh: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onSettings = onSettings
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.preferredSize))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.preferredSize.width),
            view.heightAnchor.constraint(equalToConstant: Self.preferredSize.height),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func render(snapshot: WeatherSnapshot?, isLoading: Bool, error: Error?) {
        preferredContentSize = Self.preferredSize
        view.setFrameSize(Self.preferredSize)
        self.snapshot = snapshot
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        stack.addArrangedSubview(header(snapshot: snapshot, isLoading: isLoading, error: error))

        if let error {
            stack.addArrangedSubview(label("Error: \(error.localizedDescription)", style: .secondary))
        }

        if let snapshot {
            let content = NSStackView()
            content.orientation = .horizontal
            content.spacing = 14
            content.distribution = .fill
            content.alignment = .top

            let days = NSStackView()
            days.orientation = .vertical
            days.spacing = 3
            days.widthAnchor.constraint(equalToConstant: Metrics.dayPaneWidth).isActive = true
            for day in snapshot.daily.prefix(7) {
                let row = DayRowView(day: day) { [weak self] day in
                    self?.renderDetails(for: day)
                }
                days.addArrangedSubview(row)
            }

            detailStack.orientation = .vertical
            detailStack.spacing = 6
            detailStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            detailStack.wantsLayer = true
            detailStack.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            detailStack.layer?.cornerRadius = 8
            detailStack.widthAnchor.constraint(equalToConstant: Metrics.detailPaneWidth).isActive = true

            let detailScroll = NSScrollView()
            detailScroll.drawsBackground = false
            detailScroll.borderType = .noBorder
            detailScroll.hasVerticalScroller = true
            detailScroll.autohidesScrollers = true
            detailScroll.documentView = detailStack
            detailScroll.widthAnchor.constraint(equalToConstant: Metrics.detailPaneWidth).isActive = true
            detailScroll.heightAnchor.constraint(equalToConstant: Metrics.contentHeight).isActive = true

            content.addArrangedSubview(days)
            content.addArrangedSubview(detailScroll)
            content.heightAnchor.constraint(equalToConstant: Metrics.contentHeight).isActive = true
            stack.addArrangedSubview(content)

            if let first = snapshot.daily.first {
                renderDetails(for: first)
            }
        } else {
            stack.addArrangedSubview(label("Weather will appear after the first refresh.", style: .secondary))
        }

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(actions())
    }

    private func header(snapshot: WeatherSnapshot?, isLoading: Bool, error: Error?) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10

        let iconName = snapshot?.current.condition.symbolName ?? "cloud"
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.spacing = 2
        if let snapshot {
            copy.addArrangedSubview(label(currentTitle(snapshot), style: .title))
            copy.addArrangedSubview(label(locationLine(snapshot, isLoading: isLoading), style: .secondary))
            if let station = snapshot.current.observationStation {
                copy.addArrangedSubview(label("Current from \(station.identifier) \(station.distanceMiles.map { String(format: "%.1f mi", $0) } ?? "")", style: .secondary))
            }
        } else {
            copy.addArrangedSubview(label(isLoading ? "Refreshing..." : "WeatherBar", style: .title))
            copy.addArrangedSubview(label(error?.localizedDescription ?? "Waiting for weather data", style: .secondary))
        }

        container.addArrangedSubview(icon)
        container.addArrangedSubview(copy)
        return container
    }

    private func actions() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.addArrangedSubview(button("Refresh Now", action: #selector(refreshTapped)))
        row.addArrangedSubview(button("Settings", action: #selector(settingsTapped)))
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(button("Quit", action: #selector(quitTapped)))
        return row
    }

    private func renderDetails(for day: DailyForecast) {
        detailStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        detailStack.addArrangedSubview(label(dayTitle(day), style: .headline))
        detailStack.addArrangedSubview(label(detailLine(day), style: .secondary))

        if let sunrise = day.sunrise, let sunset = day.sunset {
            detailStack.addArrangedSubview(label("Sunrise \(timeFormatter.string(from: sunrise)) • Sunset \(timeFormatter.string(from: sunset))", style: .secondary))
        }

        if let uv = day.uvIndexMax {
            detailStack.addArrangedSubview(label("Max UV \(String(format: "%.1f", uv)) • \(uvRisk(uv))", style: .secondary))
        }

        let hours = day.hourly.filter { calendar.component(.hour, from: $0.startTime) >= 6 }.prefix(14)
        for hour in hours {
            detailStack.addArrangedSubview(label(hourTitle(hour), style: .mono))
        }
        let height = max(Metrics.contentHeight, detailStack.fittingSize.height)
        detailStack.frame = NSRect(
            x: 0,
            y: 0,
            width: Metrics.detailPaneWidth,
            height: height
        )
    }

    private func currentTitle(_ snapshot: WeatherSnapshot) -> String {
        var bits = ["\(snapshot.current.temperatureF)°F", snapshot.current.summary]
        if let apparent = snapshot.current.apparentTemperatureF {
            bits.append("feels \(apparent)°")
        }
        if let precip = snapshot.current.precipitationChance {
            bits.append("\(precip)% precip")
        }
        return bits.joined(separator: " • ")
    }

    private func locationLine(_ snapshot: WeatherSnapshot, isLoading: Bool) -> String {
        var bits = [snapshot.locationName ?? "Current location"]
        if let accuracy = snapshot.locationAccuracyMeters {
            bits.append("±\(Int(accuracy.rounded())) m")
        }
        bits.append("\(snapshot.sourceDescription)")
        if isLoading {
            bits.append("refreshing")
        } else {
            bits.append("updated \(timeFormatter.string(from: snapshot.fetchedAt))")
        }
        return bits.joined(separator: " • ")
    }

    private func dayTitle(_ day: DailyForecast) -> String {
        let precip = day.precipitationChance.map { " • \($0)%" } ?? ""
        return "\(dayFormatter.string(from: day.date)): \(day.lowF)°/\(day.highF)° • \(day.summary)\(precip)"
    }

    private func detailLine(_ day: DailyForecast) -> String {
        var bits: [String] = []
        if let apparentLow = day.apparentLowF, let apparentHigh = day.apparentHighF {
            bits.append("Feels \(apparentLow)°/\(apparentHigh)°")
        }
        if let precip = day.precipitationAmountInches {
            bits.append(String(format: "%.2f in precip", precip))
        }
        if let daylight = day.daylightDurationSeconds {
            bits.append("Daylight \(Int(daylight / 3600))h \(Int(daylight.truncatingRemainder(dividingBy: 3600) / 60))m")
        }
        if let wind = day.wind {
            bits.append(wind.displayText)
        }
        return bits.isEmpty ? "No additional daily details available." : bits.joined(separator: " • ")
    }

    private func hourTitle(_ hour: HourlyForecast) -> String {
        var bits = ["\(timeFormatter.string(from: hour.startTime)): \(hour.temperatureF)°", hour.summary]
        if let uv = hour.uvIndex, uv > 0 {
            bits.append("UV \(String(format: "%.1f", uv))")
        }
        if let precip = hour.precipitationChance {
            bits.append("\(precip)% precip")
        }
        if let humidity = hour.humidity {
            bits.append("\(humidity)% RH")
        }
        if let wind = hour.wind {
            bits.append(wind.displayText)
        }
        return bits.joined(separator: " • ")
    }

    private func uvRisk(_ uv: Double) -> String {
        switch uv {
        case ..<3: return "Low"
        case ..<6: return "Moderate"
        case ..<8: return "High"
        case ..<11: return "Very High"
        default: return "Extreme"
        }
    }

    private func label(_ text: String, style: LabelStyle) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = style == .mono ? 1 : 2
        switch style {
        case .title:
            field.font = .systemFont(ofSize: 20, weight: .semibold)
        case .headline:
            field.font = .systemFont(ofSize: 14, weight: .semibold)
        case .secondary:
            field.font = .systemFont(ofSize: 12)
            field.textColor = .secondaryLabelColor
        case .mono:
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = .secondaryLabelColor
        }
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func refreshTapped() { onRefresh() }
    @objc private func settingsTapped() { onSettings() }
    @objc private func quitTapped() { onQuit() }

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private enum LabelStyle {
        case title
        case headline
        case secondary
        case mono
    }

    private enum Metrics {
        static let contentHeight: CGFloat = 350
        static let dayPaneWidth: CGFloat = 280
        static let detailPaneWidth: CGFloat = 292
    }
}

final class DayRowView: NSView {
    private let onHover: (DailyForecast) -> Void
    private let day: DailyForecast
    private let label: NSTextField

    init(day: DailyForecast, onHover: @escaping (DailyForecast) -> Void) {
        self.day = day
        self.onHover = onHover
        self.label = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        label.stringValue = "\(Self.dayFormatter.string(from: day.date)): \(day.lowF)°/\(day.highF)° • \(day.summary) • \(day.precipitationChance.map { "\($0)%" } ?? "--")"
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        label.textColor = .selectedMenuItemTextColor
        onHover(day)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        label.textColor = .labelColor
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
