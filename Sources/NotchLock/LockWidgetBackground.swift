import AppKit
import SwiftUI

enum LockWidgetMetrics {
    static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 16
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

    private func frosted(_ content: Content) -> some View {
        content
            .background(VisualEffectBackground(material: .hudWindow).clipShape(shape))
            .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
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
