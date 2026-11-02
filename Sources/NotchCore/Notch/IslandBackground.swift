import AppKit
import SwiftUI

/// The island's fill for the chosen theme, plus the drop shadow that lifts it off the screen.
struct IslandBackground: View {
    let shape: NotchShape
    let theme: NotchTheme
    /// Height of the solid black band at the top of a glass island, so it grows out of the camera housing
    /// instead of floating next to it. Zero on displays with nothing to merge with.
    let cap: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    /// A light wash keeps the Liquid Glass look while helping the white content on bright wallpapers.
    private static let tint = 0.2
    /// Points below the cap over which black dissolves into glass.
    private static let capFade: CGFloat = 40

    var body: some View {
        switch theme {
        case .classic:
            shape.fill(.black).shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        case .glass:
            ZStack {
                // The shadow is cast by a ring with the island cut out: anything solid behind the glass would show through it.
                shape.fill(.black)
                    .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
                    .mask {
                        ZStack {
                            Rectangle().padding(-80)
                            shape.blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                glass
                if cap > 0 {
                    GeometryReader { proxy in
                        shape.fill(LinearGradient(stops: capStops(height: proxy.size.height), startPoint: .top, endPoint: .bottom))
                    }
                }
            }
        }
    }

    /// Solid black down to the cap, then a fade; a closed island is no taller than the cap, so it stays all black.
    private func capStops(height: CGFloat) -> [Gradient.Stop] {
        guard height > cap else { return [.init(color: .black, location: 0), .init(color: .black, location: 1)] }
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: cap / height),
            .init(color: .clear, location: min(1, (cap + Self.capFade) / height)),
        ]
    }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26, *) {
            Color.clear
                .glassEffect(.regular.tint(.black.opacity(Self.tint)), in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            frosted
        }
    }

    /// Blur of what is behind the window, the dark wash, and a faint rim so the edge reads against busy backgrounds.
    private var frosted: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow).clipShape(shape)
            shape.fill(.black.opacity(Self.tint))
            shape.stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

/// Blurs whatever is behind the window, always in the dark appearance.
public struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    public init(material: NSVisualEffectView.Material) {
        self.material = material
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
