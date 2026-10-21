import SwiftUI

/// Standard scaffold for a settings pane so every feature's pane looks the same.
public struct SettingsPaneView<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }
}

/// A toggle row with an optional secondary description line.
public struct SettingsToggle: View {
    let title: String
    let info: String?
    @Binding var isOn: Bool

    public init(_ title: String, info: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.info = info
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let info {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A slider row showing its current value, for durations and offsets.
public struct SettingsSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    public init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.1, format: @escaping (Double) -> String = { String(format: "%.1fs", $0) }) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.format = format
    }

    public var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).frame(minWidth: 140)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            }
        }
    }
}

/// Rounded colored SF Symbol tile, as used in the settings sidebar.
public struct SettingsIcon: View {
    let symbol: String
    let color: Color

    public init(symbol: String, color: Color) {
        self.symbol = symbol
        self.color = color
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
