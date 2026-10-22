import AppKit
import Observation
import SwiftUI
import NotchCore

enum HUDKind: String, CaseIterable, Sendable {
    case volume, brightness, keyboard

    var activityID: String { "hud.\(rawValue)" }

    var category: ActivityCategory {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        case .keyboard: .keyboardBacklight
        }
    }

    var enabledKey: SettingKey<Bool> {
        switch self {
        case .volume: HUDSettings.enableVolume
        case .brightness: HUDSettings.enableBrightness
        case .keyboard: HUDSettings.enableKeyboard
        }
    }

    var isEnabled: Bool { Defaults[enabledKey] }

    var levelColorsKey: SettingKey<Bool> {
        switch self {
        case .volume: HUDSettings.levelColorsVolume
        case .brightness: HUDSettings.levelColorsBrightness
        case .keyboard: HUDSettings.levelColorsKeyboard
        }
    }

    /// Level coloring for this kind, or nil when it is off for this kind.
    var levelColors: LevelColors? {
        let colors = HUDSettings.levelColors
        guard colors.mode != .off, Defaults[levelColorsKey] else { return nil }
        return colors
    }
}

@MainActor
@Observable
final class HUDLevelModel {
    let kind: HUDKind
    var value: Double = 0
    var symbol = "speaker.wave.2.fill"
    var isDimmed = false
    /// Bumped when level color settings change so open HUDs repaint.
    var colorRevision = 0

    init(kind: HUDKind) {
        self.kind = kind
    }
}

/// Builds and presents the level HUDs. Each kind keeps one model so repeated presses animate in place.
@MainActor
final class HUDPresenter {
    private var models: [HUDKind: HUDLevelModel] = [:]
    private var colorObserver: AnyObject?

    init() {
        colorObserver = Defaults.observe(HUDSettings.levelColorKeys) { [weak self] in
            self?.models.values.forEach { $0.colorRevision += 1 }
        }
    }

    static let outputActivityID = "hud.output"

    func isVisible(_ kind: HUDKind) -> Bool {
        ActivityCenter.shared.isPresented(id: kind.activityID)
    }

    func show(_ kind: HUDKind, value: Double, symbol: String, dimmed: Bool = false) {
        guard kind.isEnabled else { return }
        let model = models[kind] ?? HUDLevelModel(kind: kind)
        models[kind] = model
        let visible = isVisible(kind)
        let showPercentage = Defaults[HUDSettings.showPercentage]
        let wing: CGFloat = showPercentage ? 98 : 86
        ActivityCenter.shared.present(LiveActivity(
            id: kind.activityID,
            category: kind.category,
            priority: .high,
            duration: Defaults[HUDSettings.duration],
            leadingWidth: wing,
            trailingWidth: wing,
            leading: { HUDLeadingView(model: model) },
            trailing: { HUDTrailingView(model: model, showPercentage: showPercentage) }
        ))
        var transaction = Transaction(animation: visible ? Defaults[HUDSettings.speed].animation : nil)
        // NotchProgressBar carries its own implicit animation; this lets the speed setting win.
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.value = min(max(value, 0), 1)
            model.symbol = symbol
            model.isDimmed = dimmed
        }
    }

    func showOutput(_ device: AudioOutputDevice) {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textWidth = (device.name as NSString).size(withAttributes: [.font: font]).width
        let wing = min(max(ceil(textWidth) + 4, 64), 140)
        ActivityCenter.shared.present(LiveActivity(
            id: Self.outputActivityID,
            category: .connectivity,
            priority: .normal,
            duration: Defaults[CoreSettings.activityDuration],
            leadingWidth: wing,
            trailingWidth: wing,
            leading: {
                Image(systemName: device.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            },
            trailing: {
                MarqueeText(device.name, font: .system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        ))
    }

    func dismissAll() {
        HUDKind.allCases.forEach { ActivityCenter.shared.dismiss(id: $0.activityID) }
        ActivityCenter.shared.dismiss(id: Self.outputActivityID)
    }

    // MARK: Symbols

    static func volumeSymbol(level: Double, muted: Bool, device: AudioOutputDevice?) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if let device, device.kind.isPersonal || device.kind == .airplay { return device.symbol }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    static func brightnessSymbol(level: Double) -> String {
        level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }

    static func keyboardSymbol(level: Double) -> String {
        level < 0.5 ? "light.min" : "light.max"
    }
}

struct HUDLeadingView: View {
    let model: HUDLevelModel

    var body: some View {
        _ = model.colorRevision
        let colors = model.kind.levelColors
        let tint = Defaults[HUDSettings.levelColorsTintIcon] && !model.isDimmed ? colors?.color(at: model.value) : nil
        return Image(systemName: model.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint ?? .white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, alignment: .center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct HUDTrailingView: View {
    let model: HUDLevelModel
    let showPercentage: Bool
    @AppStorage(CoreSettings.hudProgressStyle) private var style

    private var levelColors: LevelColors? {
        _ = model.colorRevision
        return model.kind.levelColors
    }

    var body: some View {
        let value = model.isDimmed ? 0 : model.value
        HStack(spacing: 6) {
            NotchProgressBar(value: value, style: style, levelColors: levelColors)
                .frame(width: showPercentage ? 52 : 80)
            if showPercentage {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .opacity(model.isDimmed ? 0.55 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
