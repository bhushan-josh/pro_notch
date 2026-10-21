import AppKit
import NotchCore
import SwiftUI

enum WingText {
    static let size: CGFloat = 12
    static let font = Font.system(size: size, weight: .semibold)

    /// Wings have fixed widths, so text is measured up front to size them.
    static func width(_ text: String, size: CGFloat = WingText.size, weight: NSFont.Weight = .semibold) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }
}

struct LeadingWing<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct TrailingWing<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

/// Battery outline whose fill tracks the exact level, unlike the SF Symbol steps.
struct BatteryGlyph: View {
    let level: Double
    var tint: Color = .white
    var frameColor: Color = .white.opacity(0.45)
    var width: CGFloat = 23
    var height: CGFloat = 11.5

    var body: some View {
        let clamped = min(max(level, 0), 1)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .strokeBorder(frameColor, lineWidth: 1)
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                        .fill(tint)
                        .frame(width: max(clamped > 0 ? 1.5 : 0, proxy.size.width * clamped))
                }
                .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(frameColor)
                .frame(width: 1.5, height: height * 0.38)
        }
        .animation(.notchSnappy, value: clamped)
    }

    static let totalWidth: CGFloat = 25.5
}

enum DurationText {
    static func minutes(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}
