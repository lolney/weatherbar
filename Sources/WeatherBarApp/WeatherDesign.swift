import AppKit
import WeatherBarCore

enum WeatherPalette {
    static let glassOverlay = dynamic(
        light: NSColor(calibratedRed: 0.90, green: 0.95, blue: 0.92, alpha: 0.20),
        dark: NSColor(calibratedRed: 0.03, green: 0.11, blue: 0.11, alpha: 0.28)
    )
    static let panelFill = dynamic(
        light: NSColor(calibratedRed: 0.94, green: 0.98, blue: 0.96, alpha: 0.38),
        dark: NSColor(calibratedRed: 0.05, green: 0.13, blue: 0.13, alpha: 0.42)
    )
    static let panelStroke = dynamic(
        light: NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.43, alpha: 0.24),
        dark: NSColor(calibratedRed: 0.55, green: 0.80, blue: 0.78, alpha: 0.22)
    )
    static let rowFill = dynamic(
        light: NSColor(calibratedRed: 0.98, green: 0.99, blue: 0.96, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.14, alpha: 0.22)
    )
    static let rowHoverFill = dynamic(
        light: NSColor(calibratedRed: 0.12, green: 0.49, blue: 0.48, alpha: 0.18),
        dark: NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.60, alpha: 0.28)
    )
    static let rowStroke = dynamic(
        light: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.40, alpha: 0.14),
        dark: NSColor(calibratedRed: 0.65, green: 0.85, blue: 0.82, alpha: 0.16)
    )
    static let ink = dynamic(
        light: NSColor(calibratedRed: 0.06, green: 0.14, blue: 0.15, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.86, green: 0.95, blue: 0.93, alpha: 1.0)
    )
    static let secondaryInk = dynamic(
        light: NSColor(calibratedRed: 0.33, green: 0.41, blue: 0.42, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.62, green: 0.76, blue: 0.74, alpha: 1.0)
    )
    static let teal = NSColor(calibratedRed: 0.02, green: 0.48, blue: 0.49, alpha: 1.0)
    static let coral = NSColor(calibratedRed: 0.82, green: 0.22, blue: 0.18, alpha: 1.0)
    static let citron = NSColor(calibratedRed: 0.66, green: 0.62, blue: 0.18, alpha: 1.0)
    static let sky = NSColor(calibratedRed: 0.24, green: 0.50, blue: 0.70, alpha: 1.0)
    static let mist = NSColor(calibratedRed: 0.50, green: 0.64, blue: 0.62, alpha: 1.0)
    static let plum = NSColor(calibratedRed: 0.43, green: 0.34, blue: 0.52, alpha: 1.0)

    static func accent(for condition: WeatherCondition) -> NSColor {
        switch condition {
        case .sunny:
            return citron
        case .partlyCloudy:
            return teal
        case .cloudy, .fog:
            return mist
        case .rain, .sleet:
            return sky
        case .thunderstorm:
            return plum
        case .snow:
            return NSColor(calibratedRed: 0.58, green: 0.72, blue: 0.78, alpha: 1.0)
        case .wind:
            return coral
        case .unknown:
            return .tertiaryLabelColor
        }
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

final class RoundedFillView: NSView {
    var fillColor: NSColor {
        didSet {
            layer?.backgroundColor = fillColor.cgColor
        }
    }

    init(fillColor: NSColor, radius: CGFloat) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.backgroundColor = fillColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
