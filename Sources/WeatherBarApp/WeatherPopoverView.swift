import SwiftUI
import WeatherBarCore

struct WeatherPopoverView: View {
    @ObservedObject var state: WeatherPopoverState

    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onSelectLocation: (String) -> Void
    let onAddLocation: () -> Void
    let onQuit: () -> Void

    @State private var selectedDayID: Date?

    private var selectedDay: DailyForecast? {
        guard let snapshot = state.snapshot else { return nil }
        if let selectedDayID,
           let day = snapshot.daily.first(where: { $0.id == selectedDayID }) {
            return day
        }
        return snapshot.daily.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = state.error {
                Text("Error: \(error.localizedDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let snapshot = state.snapshot {
                forecastContent(snapshot)
            } else {
                Text("Weather will appear after the first refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Divider()
            actions
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(.ultraThinMaterial)
        .overlay {
            Color(nsColor: WeatherPalette.glassOverlay)
                .allowsHitTesting(false)
        }
        .onChange(of: state.snapshot?.daily.first?.id) { _, newValue in
            selectedDayID = newValue
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: state.snapshot?.current.condition.symbolName ?? "cloud")
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: state.snapshot.map { WeatherPalette.accent(for: $0.current.condition) } ?? WeatherPalette.teal))
                .frame(width: 32)
                .accessibilityLabel(state.snapshot?.current.summary ?? "Weather")

            VStack(alignment: .leading, spacing: 1) {
                if let snapshot = state.snapshot {
                    Text(currentTitle(snapshot))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                        .lineLimit(1)
                    Text(locationLine(snapshot))
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                        .lineLimit(1)
                    if let station = snapshot.current.observationStation {
                        Text("Current from \(station.identifier) \(station.distanceMiles.map { String(format: "%.1f mi", $0) } ?? "")")
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                            .lineLimit(1)
                    }
                } else {
                    Text(state.isLoading ? "Refreshing..." : "WeatherBar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                    Text(state.error?.localizedDescription ?? "Waiting for weather data")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func forecastContent(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                ForEach(snapshot.daily.prefix(7)) { day in
                    ForecastDayRow(
                        day: day,
                        isSelected: selectedDay?.id == day.id,
                        onSelect: { selectedDayID = day.id }
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(width: Metrics.dayPaneWidth, height: Metrics.contentHeight, alignment: .top)

            if let selectedDay {
                ForecastDetailView(day: selectedDay)
                    .frame(width: Metrics.detailPaneWidth, height: Metrics.contentHeight)
            }
        }
        .frame(height: Metrics.contentHeight)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            locationMenu
            Button("Refresh Now", action: onRefresh)
            Button("Settings", action: onSettings)
            Spacer()
            Button("Quit", action: onQuit)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    private var locationMenu: some View {
        Menu {
            Button("Current Location") {
                onSelectLocation(AppSettings.currentLocationID)
            }
            if !state.savedLocations.isEmpty {
                Divider()
                ForEach(state.savedLocations) { location in
                    Button(location.name) {
                        onSelectLocation(location.id)
                    }
                }
            }
            Divider()
            Button("Add Location...", action: onAddLocation)
        } label: {
            Label(selectedLocationName, systemImage: "location")
                .lineLimit(1)
        }
        .frame(maxWidth: 210, alignment: .leading)
    }

    private var selectedLocationName: String {
        if state.selectedLocationID == AppSettings.currentLocationID {
            return "Current Location"
        }
        return state.savedLocations.first(where: { $0.id == state.selectedLocationID })?.name ?? "Location"
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

    private func locationLine(_ snapshot: WeatherSnapshot) -> String {
        var bits = [snapshot.locationName ?? "Current location"]
        if let accuracy = snapshot.locationAccuracyMeters {
            bits.append("±\(Int(accuracy.rounded())) m")
        }
        bits.append(snapshot.sourceDescription)
        bits.append(state.isLoading ? "refreshing" : "updated \(Self.timeFormatter.string(from: snapshot.fetchedAt))")
        return bits.joined(separator: " • ")
    }

    private enum Metrics {
        static let contentHeight: CGFloat = 440
        static let dayPaneWidth: CGFloat = 280
        static let detailPaneWidth: CGFloat = 420
    }

    private static let preferredSize = CGSize(width: 760, height: 600)
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct ForecastDayRow: View {
    let day: DailyForecast
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var isActive: Bool { isSelected || isHovered }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color(nsColor: WeatherPalette.accent(for: day.condition)))
                    .frame(width: 4, height: 24)

                Text(Self.dayFormatter.string(from: day.date))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                    .frame(width: 34, alignment: .leading)

                Text("\(day.lowF)°/\(day.highF)°  \(day.summary)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: isActive ? WeatherPalette.ink : WeatherPalette.secondaryInk))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(day.precipitationChance.map { "\($0)%" } ?? "--")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: WeatherPalette.accent(for: day.condition)))
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: isActive ? WeatherPalette.rowHoverFill : WeatherPalette.rowFill))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: WeatherPalette.rowStroke), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onSelect()
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

private struct ForecastDetailView: View {
    let day: DailyForecast

    private var hours: [HourlyForecast] {
        day.hourly.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayTitle(day))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                .lineLimit(2)

            DailyMetricsStrip(day: day)

            if hours.isEmpty {
                Text("No hourly detail available.")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                Spacer(minLength: 0)
            } else {
                HourlyTable(hours: hours)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: WeatherPalette.panelStroke), lineWidth: 1)
        }
    }

    private func dayTitle(_ day: DailyForecast) -> String {
        let precip = day.precipitationChance.map { " • \($0)%" } ?? ""
        return "\(Self.dayFormatter.string(from: day.date)): \(day.lowF)°/\(day.highF)° • \(day.summary)\(precip)"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
}

private struct DailyMetricsStrip: View {
    let day: DailyForecast

    var body: some View {
        HStack(spacing: 6) {
            if let apparentLow = day.apparentLowF, let apparentHigh = day.apparentHighF {
                MetricPill(label: "Feels", value: "\(apparentLow)°/\(apparentHigh)°")
            }
            if let precip = day.precipitationAmountInches {
                MetricPill(label: "Rain", value: String(format: "%.2f in", precip))
            }
            if let daylight = day.daylightDurationSeconds {
                MetricPill(
                    label: "Light",
                    value: "\(Int(daylight / 3600))h \(Int(daylight.truncatingRemainder(dividingBy: 3600) / 60))m"
                )
            }
            if let uv = day.uvIndexMax {
                MetricPill(label: "UV", value: String(format: "%.1f", uv), color: uvColor(uv))
            }
            if let sunrise = day.sunrise, let sunset = day.sunset {
                MetricPill(
                    label: "Sun",
                    value: "\(Self.timeFormatter.string(from: sunrise))-\(Self.timeFormatter.string(from: sunset))"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func uvColor(_ uv: Double) -> Color {
        switch uv {
        case ..<3:
            return Color(nsColor: WeatherPalette.teal)
        case ..<6:
            return Color(nsColor: WeatherPalette.citron)
        case ..<8:
            return Color(nsColor: WeatherPalette.coral)
        default:
            return Color(nsColor: WeatherPalette.plum)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()
}

private struct MetricPill: View {
    let label: String
    let value: String
    var color: Color = Color(nsColor: WeatherPalette.secondaryInk)

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: WeatherPalette.rowFill), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: WeatherPalette.rowStroke), lineWidth: 0.5)
        }
    }
}

private struct HourlyTable: View {
    let hours: [HourlyForecast]

    private var temperatureRange: ClosedRange<Int> {
        let values = hours.map(\.temperatureF)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? minValue
        return minValue...max(maxValue, minValue + 1)
    }

    private var compact: Bool { hours.count > 18 }

    var body: some View {
        VStack(spacing: 0) {
            HourlyHeader()
                .padding(.bottom, 3)

            ForEach(hours) { hour in
                HourlyTableRow(
                    hour: hour,
                    temperatureRange: temperatureRange,
                    rowHeight: compact ? 12.5 : 15,
                    fontSize: compact ? 9.5 : 10.5
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HourlyHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Time").frame(width: 42, alignment: .leading)
            Text("").frame(width: 16)
            Text("Temp").frame(width: 92, alignment: .leading)
            Text("Rain").frame(width: 58, alignment: .leading)
            Text("UV").frame(width: 38, alignment: .leading)
            Text("Wind").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

private struct HourlyTableRow: View {
    let hour: HourlyForecast
    let temperatureRange: ClosedRange<Int>
    let rowHeight: CGFloat
    let fontSize: CGFloat

    private var temperatureFraction: Double {
        let span = max(1, temperatureRange.upperBound - temperatureRange.lowerBound)
        return Double(hour.temperatureF - temperatureRange.lowerBound) / Double(span)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: hour.startTime))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .frame(width: 42, alignment: .leading)

            Image(systemName: hour.condition.symbolName)
                .font(.system(size: fontSize + 1, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: WeatherPalette.accent(for: hour.condition)))
                .frame(width: 16)
                .accessibilityLabel(hour.summary)

            TemperatureCell(
                temperatureF: hour.temperatureF,
                fraction: temperatureFraction,
                fontSize: fontSize,
                color: Color(nsColor: WeatherPalette.accent(for: hour.condition))
            )
            .frame(width: 92)

            PrecipCell(chance: hour.precipitationChance, fontSize: fontSize)
                .frame(width: 58)

            UVCell(value: hour.uvIndex, fontSize: fontSize)
                .frame(width: 38)

            Text(hour.wind?.displayText ?? "-")
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: rowHeight)
        .accessibilityElement(children: .combine)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()
}

private struct TemperatureCell: View {
    let temperatureF: Int
    let fraction: Double
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(temperatureF)°")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                .frame(width: 28, alignment: .trailing)

            GeometryReader { proxy in
                let xPosition = max(2, min(proxy.size.width - 2, proxy.size.width * fraction))
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: WeatherPalette.rowStroke))
                        .frame(height: 1)
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .offset(x: xPosition - 2.5)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct PrecipCell: View {
    let chance: Int?
    let fontSize: CGFloat

    private var fraction: Double {
        Double(chance ?? 0) / 100
    }

    var body: some View {
        HStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: WeatherPalette.rowStroke))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color(nsColor: WeatherPalette.sky))
                        .frame(width: max(1, proxy.size.width * fraction), height: 3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 24, height: 7)

            Text(chance.map { "\($0)" } ?? "-")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .frame(width: 24, alignment: .trailing)
        }
    }
}

private struct UVCell: View {
    let value: Double?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(value.map { String(format: "%.1f", $0) } ?? "-")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
        guard let value else {
            return .secondary.opacity(0.35)
        }
        switch value {
        case ..<3:
            return Color(nsColor: WeatherPalette.teal)
        case ..<6:
            return Color(nsColor: WeatherPalette.citron)
        case ..<8:
            return Color(nsColor: WeatherPalette.coral)
        default:
            return Color(nsColor: WeatherPalette.plum)
        }
    }
}
