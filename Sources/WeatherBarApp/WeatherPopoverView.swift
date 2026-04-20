import SwiftUI
import WeatherBarCore

struct WeatherPopoverView: View {
    @ObservedObject var state: WeatherPopoverState

    let onRefresh: () -> Void
    let onSettings: () -> Void
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
            Button("Refresh Now", action: onRefresh)
            Button("Settings", action: onSettings)
            Spacer()
            Button("Quit", action: onQuit)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
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
        static let contentHeight: CGFloat = 330
        static let dayPaneWidth: CGFloat = 280
        static let detailPaneWidth: CGFloat = 292
    }

    private static let preferredSize = CGSize(width: 620, height: 490)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                Text(dayTitle(day))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: WeatherPalette.ink))
                    .lineLimit(2)

                Text(detailLine(day))
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                    .lineLimit(3)

                if let sunrise = day.sunrise, let sunset = day.sunset {
                    Text("Sunrise \(Self.timeFormatter.string(from: sunrise)) • Sunset \(Self.timeFormatter.string(from: sunset))")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                }

                if let uv = day.uvIndexMax {
                    Text("Max UV \(String(format: "%.1f", uv)) • \(uvRisk(uv))")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                }

                ForEach(day.hourly.filter { Self.calendar.component(.hour, from: $0.startTime) >= 6 }.prefix(14)) { hour in
                    Text(hourTitle(hour))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: WeatherPalette.secondaryInk))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
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
        var bits = ["\(Self.timeFormatter.string(from: hour.startTime)): \(hour.temperatureF)°", hour.summary]
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

    private static let calendar = Calendar.current
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
