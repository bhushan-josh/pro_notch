import SwiftUI

/// Horizontal level bar used by HUDs and media progress. `value` is 0...1.
public struct NotchProgressBar: View {
    let value: Double
    let style: ProgressStyle
    let tint: Color?
    let height: CGFloat

    public init(value: Double, style: ProgressStyle = Defaults[CoreSettings.hudProgressStyle], tint: Color? = nil, height: CGFloat = 5) {
        self.value = min(max(value, 0), 1)
        self.style = style
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(fill)
                    .frame(width: max(height, proxy.size.width * value))
                    .shadow(color: style == .glow ? fillColor.opacity(0.8) : .clear, radius: style == .glow ? 5 : 0)
            }
        }
        .frame(height: height)
        .animation(.notchSnappy, value: value)
    }

    private var fillColor: Color {
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
