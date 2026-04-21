import SwiftUI
import WeatherBarCore

struct WeatherPopoverView: View {
    private static let addLocationSelectionID = "__add_location__"

    @ObservedObject var state: WeatherPopoverState

    let onRefresh: () -> Void
    let onSettings: () -> Void
    let onSelectLocation: (String) -> Void
    let onAddLocation: () -> Void
    let onQuit: () -> Void

    @State private var selectedDayID: Date?
    @State private var locationMenuSelection = AppSettings.currentLocationID

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
        .onAppear {
            locationMenuSelection = state.selectedLocationID
        }
        .onChange(of: state.snapshot?.daily.first?.id) { _, newValue in
            selectedDayID = newValue
        }
        .onChange(of: state.selectedLocationID) { _, newValue in
            locationMenuSelection = newValue
        }
        .onChange(of: locationMenuSelection) { _, newValue in
            guard newValue != state.selectedLocationID else { return }
            if newValue == Self.addLocationSelectionID {
                locationMenuSelection = state.selectedLocationID
                onAddLocation()
            } else {
                onSelectLocation(newValue)
            }
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: WeatherPalette.panelStroke), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        Picker(selection: $locationMenuSelection) {
            Text("Current Location").tag(AppSettings.currentLocationID)
            ForEach(state.savedLocations) { location in
                Text(location.name).tag(location.id)
            }
            Text("Add Location...").tag(Self.addLocationSelectionID)
        } label: {
            Label(selectedLocationName, systemImage: "location")
                .lineLimit(1)
        }
        .pickerStyle(.menu)
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
                .lineLimit(1)

            Text(daySynopsis)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .lineLimit(1)

            DailyOverviewGrid(day: day, hours: hours)

            if hours.isEmpty {
                Text("No hourly detail available.")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                Spacer(minLength: 0)
            } else {
                HourlyTrendPanel(hours: hours)
                HourlyTable(hours: hours)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayTitle(_ day: DailyForecast) -> String {
        "\(Self.dayFormatter.string(from: day.date)) • \(day.summary)"
    }

    private var daySynopsis: String {
        var bits = ["\(day.lowF)°-\(day.highF)°"]

        if let warmestHour {
            bits.append("warmest \(warmestHour.temperatureF)° \(Self.hourFormatter.string(from: warmestHour.startTime))")
        }
        if let wettestHour, let chance = wettestHour.precipitationChance, chance > 0 {
            bits.append("rain \(chance)% \(Self.hourFormatter.string(from: wettestHour.startTime))")
        }
        if let uvPeakHour, let uv = uvPeakHour.uvIndex, uv > 0.1 {
            bits.append("UV \(Self.uvFormatter.string(from: NSNumber(value: uv)) ?? String(format: "%.1f", uv)) \(Self.hourFormatter.string(from: uvPeakHour.startTime))")
        }

        return bits.joined(separator: "   ")
    }

    private var warmestHour: HourlyForecast? {
        hours.max { $0.temperatureF < $1.temperatureF }
    }

    private var wettestHour: HourlyForecast? {
        hours.max { ($0.precipitationChance ?? 0) < ($1.precipitationChance ?? 0) }
    }

    private var uvPeakHour: HourlyForecast? {
        hours.max { ($0.uvIndex ?? 0) < ($1.uvIndex ?? 0) }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    private static let uvFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct DailyOverviewGrid: View {
    let day: DailyForecast
    let hours: [HourlyForecast]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                OverviewMetric(label: "Sun", value: sunSummary)
                OverviewMetric(label: "Light", value: daylightSummary)
            }
            GridRow {
                OverviewMetric(label: "Feels", value: apparentSummary)
                OverviewMetric(label: "Rain", value: rainSummary)
            }
            GridRow {
                OverviewMetric(label: "UV", value: uvSummary, color: uvColor)
                OverviewMetric(label: "Wind", value: windSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: WeatherPalette.rowStroke))
                .frame(height: 0.5)
        }
    }

    private var sunSummary: String {
        guard let sunrise = day.sunrise, let sunset = day.sunset else { return "-" }
        return "\(Self.sunFormatter.string(from: sunrise))-\(Self.sunFormatter.string(from: sunset))"
    }

    private var daylightSummary: String {
        guard let daylight = day.daylightDurationSeconds else { return "-" }
        let hours = Int(daylight / 3600)
        let minutes = Int(daylight.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours)h \(minutes)m"
    }

    private var apparentSummary: String {
        guard let apparentLow = day.apparentLowF, let apparentHigh = day.apparentHighF else { return "-" }
        return "\(apparentLow)° to \(apparentHigh)°"
    }

    private var rainSummary: String {
        let chance = day.precipitationChance.map { "\($0)%" } ?? "-"
        if let amount = day.precipitationAmountInches {
            return "\(chance), \(String(format: "%.2f", amount)) in"
        }
        return chance
    }

    private var uvSummary: String {
        guard let uv = day.uvIndexMax else { return "-" }
        return Self.uvFormatter.string(from: NSNumber(value: uv)) ?? String(format: "%.1f", uv)
    }

    private var uvColor: Color {
        guard let uv = day.uvIndexMax else {
            return Color(nsColor: WeatherPalette.ink)
        }
        return ForecastStyling.uvColor(for: uv)
    }

    private var windSummary: String {
        if let wind = day.wind?.displayText, wind != "Wind" {
            return wind
        }
        return hours.max { ($0.wind?.speedMph ?? 0) < ($1.wind?.speedMph ?? 0) }?.wind?.displayText ?? "-"
    }

    private static let sunFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    private static let uvFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct OverviewMetric: View {
    let label: String
    let value: String
    var color: Color = Color(nsColor: WeatherPalette.ink)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HourlyTrendPanel: View {
    let hours: [HourlyForecast]

    private var temperatures: [Double] {
        hours.map { Double($0.temperatureF) }
    }

    private var precipitation: [Double] {
        hours.map { Double($0.precipitationChance ?? 0) }
    }

    private var uvValues: [Double] {
        hours.map { $0.uvIndex ?? 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TrendStripRow(
                label: "Temp",
                summary: "\(Int(temperatures.min() ?? 0))-\(Int(temperatures.max() ?? 0))°",
                contentHeight: 24
            ) {
                TemperatureSparkline(values: temperatures)
            }

            TrendStripRow(
                label: "Rain",
                summary: "\(Int(precipitation.max() ?? 0))%",
                contentHeight: 24
            ) {
                ProbabilityBarStrip(hours: hours, values: precipitation, color: Color(nsColor: WeatherPalette.sky))
            }

            TrendStripRow(
                label: "UV",
                summary: Self.uvFormatter.string(from: NSNumber(value: uvValues.max() ?? 0)) ?? "0",
                contentHeight: 14
            ) {
                UVHeatStrip(values: uvValues)
            }

            HourlyAxisLabels(hours: hours)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: WeatherPalette.rowStroke))
                .frame(height: 0.5)
        }
    }

    private static let uvFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct TrendStripRow<Content: View>: View {
    let label: String
    let summary: String
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            content()
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)

            Text(summary)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .frame(width: 58, alignment: .trailing)
        }
    }
}

private struct TemperatureSparkline: View {
    let values: [Double]

    private var range: ClosedRange<Double> {
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? minValue
        return minValue...max(maxValue, minValue + 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                let baseline = proxy.size.height * 0.68
                Rectangle()
                    .fill(Color(nsColor: WeatherPalette.rowStroke))
                    .frame(height: 0.5)
                    .offset(y: baseline)

                Path { path in
                    for index in values.indices {
                        let point = point(for: index, in: proxy.size)
                        if index == values.startIndex {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(Color(nsColor: WeatherPalette.teal), lineWidth: 1.4)

                if let hottestIndex = values.indices.max(by: { values[$0] < values[$1] }) {
                    let hottestPoint = point(for: hottestIndex, in: proxy.size)
                    TemperatureAnnotation(
                        label: "H \(Int(values[hottestIndex]))°",
                        alignment: .top,
                        point: hottestPoint,
                        width: proxy.size.width
                    )

                    Circle()
                        .fill(Color(nsColor: WeatherPalette.coral))
                        .frame(width: 4, height: 4)
                        .position(hottestPoint)
                }

                if let coldestIndex = values.indices.min(by: { values[$0] < values[$1] }) {
                    let coldestPoint = point(for: coldestIndex, in: proxy.size)
                    TemperatureAnnotation(
                        label: "L \(Int(values[coldestIndex]))°",
                        alignment: .bottom,
                        point: coldestPoint,
                        width: proxy.size.width
                    )

                    Circle()
                        .fill(Color(nsColor: WeatherPalette.sky))
                        .frame(width: 4, height: 4)
                        .position(coldestPoint)
                }
            }
        }
    }

    private func point(for index: Int, in size: CGSize) -> CGPoint {
        let xFraction = values.count <= 1 ? 0 : Double(index) / Double(values.count - 1)
        let yFraction = range.upperBound == range.lowerBound ? 0.5 : (values[index] - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGPoint(
            x: size.width * xFraction,
            y: (size.height * 0.78) - ((size.height * 0.52) * yFraction)
        )
    }
}

private struct ProbabilityBarStrip: View {
    let hours: [HourlyForecast]
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 1)
            let slotWidth = proxy.size.width / CGFloat(count)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    let fraction = max(0, min(1, values[index] / 100))
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color.opacity(0.18 + (0.72 * fraction)))
                            .frame(width: max(2, slotWidth - 1), height: max(1.5, proxy.size.height * fraction))
                    }
                    .frame(width: slotWidth, height: proxy.size.height)
                }
            }

            if let maxIndex = values.indices.max(by: { values[$0] < values[$1] }),
               values[maxIndex] > 0 {
                let fraction = max(0, min(1, values[maxIndex] / 100))
                let labelWidth: CGFloat = 64
                let xCenter = slotWidth * (CGFloat(maxIndex) + 0.5)
                let xOffset = min(
                    max(0, xCenter - (labelWidth / 2)),
                    max(0, proxy.size.width - labelWidth)
                )

                Text("\(Self.timeFormatter.string(from: hours[maxIndex].startTime)) \(Int(values[maxIndex]))%")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: WeatherPalette.sky))
                    .frame(width: labelWidth, alignment: .center)
                    .position(x: xOffset + (labelWidth / 2), y: 5)

                Path { path in
                    path.move(to: CGPoint(x: xCenter, y: 10))
                    path.addLine(to: CGPoint(x: xCenter, y: max(11, proxy.size.height - (proxy.size.height * fraction))))
                }
                .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()
}

private struct UVHeatStrip: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let count = max(values.count, 1)
            let slotWidth = proxy.size.width / CGFloat(count)
            HStack(spacing: 0) {
                ForEach(values.indices, id: \.self) { index in
                    Rectangle()
                        .fill(ForecastStyling.uvColor(for: values[index]).opacity(values[index] > 0 ? 0.9 : 0.12))
                        .frame(width: max(2, slotWidth - 0.5), height: proxy.size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private struct HourlyAxisLabels: View {
    let hours: [HourlyForecast]

    private var tickHours: [HourlyForecast] {
        guard !hours.isEmpty else { return [] }
        let candidateIndices = [0, hours.count / 3, (2 * hours.count) / 3, hours.count - 1]
        let uniqueIndices = Array(Set(candidateIndices)).sorted()
        return uniqueIndices.map { hours[$0] }
    }

    var body: some View {
        HStack {
            ForEach(Array(tickHours.enumerated()), id: \.offset) { index, hour in
                Text(Self.timeFormatter.string(from: hour.startTime))
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                if index < tickHours.count - 1 {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 36)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()
}

private struct TemperatureAnnotation: View {
    enum Alignment {
        case top
        case bottom
    }

    let label: String
    let alignment: Alignment
    let point: CGPoint
    let width: CGFloat

    var body: some View {
        let labelWidth: CGFloat = 42
        let xCenter = min(max(point.x, labelWidth / 2), max(labelWidth / 2, width - (labelWidth / 2)))

        Text(label)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
            .frame(width: labelWidth, alignment: .center)
            .position(x: xCenter, y: alignment == .top ? max(5, point.y - 8) : min(19, point.y + 8))
    }
}

private enum ForecastStyling {
    static func uvColor(for uv: Double) -> Color {
        switch uv {
        case ..<1:
            return .secondary.opacity(0.5)
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

private struct HourlyTable: View {
    let hours: [HourlyForecast]

    private var temperatureRange: ClosedRange<Int> {
        let values = hours.map(\.temperatureF)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? minValue
        return minValue...max(maxValue, minValue + 1)
    }

    private var rowHeight: CGFloat {
        let budget: CGFloat = 246
        return max(9.5, min(13.5, budget / CGFloat(max(hours.count, 1))))
    }

    private var fontSize: CGFloat {
        max(8.25, min(10.25, rowHeight - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HourlyHeader()
                .padding(.top, 1)
                .padding(.bottom, 2)

            ForEach(hours) { hour in
                HourlyTableRow(
                    hour: hour,
                    temperatureRange: temperatureRange,
                    rowHeight: rowHeight,
                    fontSize: fontSize
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct HourlyHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Hour").frame(width: 56, alignment: .leading)
            Text("Temp").frame(width: 86, alignment: .leading)
            Text("Rain").frame(width: 48, alignment: .leading)
            Text("Hum").frame(width: 34, alignment: .leading)
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
            HourCell(hour: hour, fontSize: fontSize)
                .frame(width: 56, alignment: .leading)

            TemperatureCell(
                temperatureF: hour.temperatureF,
                fraction: temperatureFraction,
                fontSize: fontSize,
                color: Color(nsColor: WeatherPalette.accent(for: hour.condition))
            )
            .frame(width: 86)

            PrecipCell(chance: hour.precipitationChance, fontSize: fontSize)
                .frame(width: 48)

            HumidityCell(value: hour.humidity, fontSize: fontSize)
                .frame(width: 34)

            Text(hour.wind?.displayText ?? "-")
                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: WeatherPalette.rowStroke).opacity(0.55))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()
}

private struct HourCell: View {
    let hour: HourlyForecast
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(Self.timeFormatter.string(from: hour.startTime))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                .frame(width: 34, alignment: .leading)

            Image(systemName: hour.condition.symbolName)
                .font(.system(size: fontSize + 0.5, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(nsColor: WeatherPalette.accent(for: hour.condition)))
                .frame(width: 12)
                .accessibilityLabel(hour.summary)
        }
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
                        .frame(height: 2.5)
                    Capsule()
                        .fill(Color(nsColor: WeatherPalette.sky))
                        .frame(width: max(1, proxy.size.width * fraction), height: 2.5)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 18, height: 6)

            Text(chance.map { "\($0)" } ?? "-")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                .frame(width: 22, alignment: .trailing)
        }
    }
}

private struct HumidityCell: View {
    let value: Int?
    let fontSize: CGFloat

    var body: some View {
        Text(value.map { "\($0)" } ?? "-")
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
