import AppKit
import SwiftUI

enum LockWidgetMetrics {
    static let width: CGFloat = 328
    static let cornerRadius: CGFloat = 28
    static let padding: CGFloat = 17
    static let spacing: CGFloat = 12
}

struct LockWidgetBackground: ViewModifier {
    let style: LockWidgetStyle

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LockWidgetMetrics.cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        switch style {
        case .clear:
            content
                .background(.black.opacity(0.28), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        case .frosted:
            frosted(content)
        case .glass:
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                frosted(content)
            }
        }
    }

    /// Blur plus three tints: a dark wash, a warm inner highlight one point in, and a darker rim.
    private func frosted(_ content: Content) -> some View {
        let inner = RoundedRectangle(cornerRadius: LockWidgetMetrics.cornerRadius - 1, style: .continuous)
        return content
            .background {
                ZStack {
                    VisualEffectBackground(material: .hudWindow).clipShape(shape)
                    shape.fill(Color(red: 0.05, green: 0.04, blue: 0.035).opacity(0.25))
                    inner.fill(Color(red: 0.11, green: 0.1, blue: 0.09).opacity(0.15)).padding(1)
                    inner.fill(Color(red: 1, green: 0.97, blue: 0.93).opacity(0.1)).padding(1)
                }
            }
    }
}

extension View {
    func lockWidgetBackground(_ style: LockWidgetStyle) -> some View {
        modifier(LockWidgetBackground(style: style))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
