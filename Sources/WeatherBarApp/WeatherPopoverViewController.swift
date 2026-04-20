import AppKit
import WeatherBarCore

final class WeatherPopoverViewController: NSViewController {
    static let preferredSize = NSSize(width: 620, height: 490)

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
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.preferredSize))
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = WeatherPalette.glassOverlay.cgColor
        view = effectView

        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
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
            content.spacing = 12
            content.distribution = .fill
            content.alignment = .top

            let days = NSStackView()
            days.orientation = .vertical
            days.spacing = 5
            days.widthAnchor.constraint(equalToConstant: Metrics.dayPaneWidth).isActive = true
            for day in snapshot.daily.prefix(7) {
                let row = DayRowView(day: day) { [weak self] day in
                    self?.renderDetails(for: day)
                }
                days.addArrangedSubview(row)
            }

            detailStack.orientation = .vertical
            detailStack.spacing = 7
            detailStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            detailStack.wantsLayer = true
            detailStack.layer?.backgroundColor = WeatherPalette.panelFill.cgColor
            detailStack.layer?.borderColor = WeatherPalette.panelStroke.cgColor
            detailStack.layer?.borderWidth = 1
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
        icon.contentTintColor = snapshot.map { WeatherPalette.accent(for: $0.current.condition) } ?? WeatherPalette.teal
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.spacing = 1
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
        preferredContentSize = Self.preferredSize
        view.setFrameSize(Self.preferredSize)
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
            field.textColor = WeatherPalette.ink
        case .headline:
            field.font = .systemFont(ofSize: 14, weight: .semibold)
            field.textColor = WeatherPalette.ink
        case .secondary:
            field.font = .systemFont(ofSize: 12)
            field.textColor = WeatherPalette.secondaryInk
            field.lineBreakMode = .byWordWrapping
        case .mono:
            field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            field.textColor = WeatherPalette.secondaryInk
        }
        return field
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
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
        static let contentHeight: CGFloat = 330
        static let dayPaneWidth: CGFloat = 280
        static let detailPaneWidth: CGFloat = 292
    }
}

final class DayRowView: NSView {
    private let onHover: (DailyForecast) -> Void
    private let day: DailyForecast
    private let accent: RoundedFillView
    private let dayLabel: NSTextField
    private let summaryLabel: NSTextField
    private let precipLabel: NSTextField

    init(day: DailyForecast, onHover: @escaping (DailyForecast) -> Void) {
        self.day = day
        self.onHover = onHover
        self.accent = RoundedFillView(fillColor: WeatherPalette.accent(for: day.condition), radius: 2)
        self.dayLabel = NSTextField(labelWithString: Self.dayFormatter.string(from: day.date))
        self.summaryLabel = NSTextField(labelWithString: "\(day.lowF)°/\(day.highF)°  \(day.summary)")
        self.precipLabel = NSTextField(labelWithString: day.precipitationChance.map { "\($0)%" } ?? "--")
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderColor = WeatherPalette.rowStroke.cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = WeatherPalette.rowFill.cgColor

        dayLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        dayLabel.textColor = WeatherPalette.ink
        dayLabel.alignment = .left
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = WeatherPalette.secondaryInk
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        precipLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        precipLabel.textColor = WeatherPalette.accent(for: day.condition)
        precipLabel.alignment = .right

        [accent, dayLabel, summaryLabel, precipLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            accent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            accent.widthAnchor.constraint(equalToConstant: 4),
            accent.heightAnchor.constraint(equalToConstant: 24),
            accent.centerYAnchor.constraint(equalTo: centerYAnchor),
            dayLabel.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 8),
            dayLabel.widthAnchor.constraint(equalToConstant: 34),
            dayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            summaryLabel.leadingAnchor.constraint(equalTo: dayLabel.trailingAnchor, constant: 6),
            summaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            precipLabel.leadingAnchor.constraint(greaterThanOrEqualTo: summaryLabel.trailingAnchor, constant: 8),
            precipLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            precipLabel.widthAnchor.constraint(equalToConstant: 36),
            precipLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        layer?.backgroundColor = WeatherPalette.rowHoverFill.cgColor
        dayLabel.textColor = WeatherPalette.ink
        summaryLabel.textColor = WeatherPalette.ink
        onHover(day)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = WeatherPalette.rowFill.cgColor
        dayLabel.textColor = WeatherPalette.ink
        summaryLabel.textColor = WeatherPalette.secondaryInk
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
