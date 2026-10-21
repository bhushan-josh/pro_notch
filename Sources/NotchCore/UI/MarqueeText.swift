import SwiftUI

/// Single-line text that scrolls horizontally when it does not fit.
public struct MarqueeText: View {
    let text: String
    let font: Font
    let speed: Double
    let pause: Double

    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    public init(_ text: String, font: Font = .system(size: 13, weight: .semibold), speed: Double = 28, pause: Double = 2) {
        self.text = text
        self.font = font
        self.speed = speed
        self.pause = pause
    }

    public var body: some View {
        let textWidth = textSize.width
        let overflow = textWidth > containerWidth + 1
        let gap: CGFloat = 32
        GeometryReader { proxy in
            TimelineView(.animation(paused: !overflow)) { context in
                let cycle = Double(textWidth + gap) / speed
                let total = cycle + pause
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
                let offset = overflow ? -CGFloat(max(0, t - pause) / cycle) * (textWidth + gap) : 0
                HStack(spacing: gap) {
                    label
                    if overflow { label }
                }
                .offset(x: offset)
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .onAppear { containerWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { containerWidth = $1 }
        }
        .frame(height: textSize.height)
        .clipped()
        .mask(fadeMask(enabled: overflow))
        .background(
            label.fixedSize().hidden()
                .onGeometryChange(for: CGSize.self, of: \.size) { textSize = $0 }
        )
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func fadeMask(enabled: Bool) -> some View {
        LinearGradient(
            stops: enabled
                ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                   .init(color: .black, location: 0.94), .init(color: .clear, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
            startPoint: .leading, endPoint: .trailing
        )
    }
}
