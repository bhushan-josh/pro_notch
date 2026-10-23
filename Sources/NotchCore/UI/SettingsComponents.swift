import SwiftUI

/// Standard scaffold for a settings pane so every feature's pane looks the same.
public struct SettingsPaneView<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        Form { content }
            .formStyle(SettingsCardFormStyle())
    }
}

/// Lays each form section out as a rounded card of rows, since the grouped style's section fill can't be restyled.
struct SettingsCardFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.header.isEmpty {
                            section.header
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.leading, 4)
                        }
                        SettingsCard {
                            ForEach(subviews: section.content) { row in
                                if row.id != section.content.first?.id {
                                    Divider().padding(.horizontal, 14)
                                }
                                row
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            }
                        }
                        if !section.footer.isEmpty {
                            section.footer
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.automatic)
        .toggleStyle(SettingsRowToggleStyle())
        .labeledContentStyle(SettingsRowLabeledContentStyle())
    }
}

private struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) { content }
            .background(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.6), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct SettingsRowToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct SettingsRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            // Menu pickers otherwise stretch across the whole row.
            configuration.content
                .fixedSize(horizontal: true, vertical: false)
        }
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

    /// Snaps to `step` itself; passing `step` to `Slider` draws a tick mark per step.
    private var snapped: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                let steps = ((newValue - range.lowerBound) / step).rounded()
                value = min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
            }
        )
    }

    public var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: snapped, in: range).frame(minWidth: 140, idealWidth: 170)
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
