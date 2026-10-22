import AppKit
import SwiftUI

public enum LevelColorMode: String, CaseIterable, Sendable {
    case off, solid, smooth, gradient

    public var title: String {
        switch self {
        case .off: "Off"
        case .solid: "Solid Steps"
        case .smooth: "Smooth Blend"
        case .gradient: "Gradient Bar"
        }
    }

    public var info: String {
        switch self {
        case .off: "The bar uses the progress style color."
        case .solid: "The whole bar switches color at each threshold."
        case .smooth: "The bar color blends continuously as the level rises."
        case .gradient: "The bar is painted low to high color along its length."
        }
    }
}

/// Green-to-red coloring of a level bar, driven by two thresholds.
public struct LevelColors: Equatable, Sendable {
    public var mode: LevelColorMode
    public var low: Color
    public var mid: Color
    public var high: Color
    /// Level (0...1) where the mid color is reached.
    public var midThreshold: Double
    /// Level (0...1) where the high color is reached.
    public var highThreshold: Double

    public init(mode: LevelColorMode, low: Color, mid: Color, high: Color, midThreshold: Double, highThreshold: Double) {
        self.mode = mode
        self.low = low
        self.mid = mid
        self.high = high
        self.midThreshold = min(max(midThreshold, 0.01), 0.99)
        self.highThreshold = min(max(highThreshold, self.midThreshold + 0.01), 1)
    }

    public func color(at level: Double) -> Color {
        let level = min(max(level, 0), 1)
        switch mode {
        case .off, .gradient:
            return low
        case .solid:
            if level >= highThreshold { return high }
            if level >= midThreshold { return mid }
            return low
        case .smooth:
            if level <= midThreshold { return low.mix(with: mid, by: level / midThreshold) }
            if level <= highThreshold { return mid.mix(with: high, by: (level - midThreshold) / (highThreshold - midThreshold)) }
            return high
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: low, location: 0),
                .init(color: mid, location: midThreshold),
                .init(color: high, location: highThreshold),
                .init(color: high, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Horizontal level bar used by HUDs and media progress. `value` is 0...1.
public struct NotchProgressBar: View {
    let value: Double
    let style: ProgressStyle
    let tint: Color?
    let height: CGFloat
    let levelColors: LevelColors?

    public init(
        value: Double,
        style: ProgressStyle = Defaults[CoreSettings.hudProgressStyle],
        tint: Color? = nil,
        height: CGFloat = 5,
        levelColors: LevelColors? = nil
    ) {
        self.value = min(max(value, 0), 1)
        self.style = style
        self.tint = tint
        self.height = height
        self.levelColors = levelColors?.mode == .off ? nil : levelColors
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = max(height, proxy.size.width * value)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                if let levelColors, levelColors.mode == .gradient {
                    levelColors.gradient
                        .frame(width: proxy.size.width)
                        .mask(alignment: .leading) { Capsule().frame(width: width) }
                        .shadow(color: style == .glow ? levelColors.color(at: value).opacity(0.8) : .clear, radius: style == .glow ? 5 : 0)
                } else {
                    Capsule()
                        .fill(fill)
                        .frame(width: width)
                        .shadow(color: style == .glow ? fillColor.opacity(0.8) : .clear, radius: style == .glow ? 5 : 0)
                }
            }
        }
        .frame(height: height)
        .animation(.notchSnappy, value: value)
    }

    private var fillColor: Color {
        if let levelColors { return levelColors.color(at: value) }
        if let tint { return tint }
        switch style {
        case .white, .glow: return .white
        case .accent, .stylized: return .accentColor
        }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .stylized:
            AnyShapeStyle(LinearGradient(colors: [fillColor.opacity(0.65), fillColor], startPoint: .leading, endPoint: .trailing))
        default:
            AnyShapeStyle(fillColor)
        }
    }
}

public extension Color {
    /// Parses "#RRGGBB" or "RRGGBB"; nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
