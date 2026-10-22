import AppKit
import NotchCore
import SwiftUI

@MainActor
public final class HUDFeature: NotchFeature {
    private let presenter = HUDPresenter()
    private let outputs = OutputDevices()
    private let volume = VolumeManager()
    private let brightness = BrightnessManager()
    private let keyboard = KeyboardBacklight()
    private let mediaKeys = MediaKeyManager()
    private let betterDisplay = BetterDisplayOSD()
    private var settingsObserver: AnyObject?
    private var pendingKeyboardRead: Task<Void, Never>?
    private var lastAccessWarning: Date?

    private static let coarseStep = 1.0 / 16
    private static let fineStep = 1.0 / 64

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        registry.register(permission: MediaKeyManager.permission)
        registry.register(settingsPane: SettingsPane(id: "hud", title: "HUD", symbol: "speaker.wave.2.fill", color: .orange, order: 20) {
            [outputs, volume] in HUDSettingsView(outputs: outputs, volume: volume)
        })

        outputs.onDefaultDeviceChange = { [weak self] device in self?.outputChanged(device) }
        outputs.start()
        volume.onExternalChange = { [weak self] in
            self?.warnIfSystemHUDLeaks()
            self?.showVolume()
        }
        volume.bind(to: outputs.defaultDeviceID)

        brightness.onExternalChange = { [weak self] value, userDriven in self?.brightnessChanged(value, userDriven: userDriven) }
        brightness.start()
        keyboard.start()

        mediaKeys.handler = { [weak self] event in self?.handle(event) ?? false }
        mediaKeys.start()

        betterDisplay.onLevel = { [weak self] level in self?.showBetterDisplay(level) }
        updateBetterDisplay()
        settingsObserver = Defaults.observe([HUDSettings.betterDisplayIntegration.name]) { [weak self] in
            self?.updateBetterDisplay()
        }
    }

    public func stop() {
        mediaKeys.stop()
        mediaKeys.handler = nil
        volume.unbind()
        outputs.stop()
        brightness.stop()
        betterDisplay.stop()
        settingsObserver = nil
        pendingKeyboardRead?.cancel()
        presenter.dismissAll()
    }

    // MARK: Accessibility warning

    /// Without Accessibility the key tap can't swallow events, so macOS draws its own HUD too. Say so in the notch.
    private func warnIfSystemHUDLeaks() {
        guard Defaults[HUDSettings.replaceSystemHUD], !mediaKeys.isInstalled else { return }
        if let last = lastAccessWarning, Date().timeIntervalSince(last) < 60 { return }
        lastAccessWarning = Date()
        ActivityCenter.shared.present(LiveActivity(
            id: "hud.accessibility",
            category: .other,
            priority: .high,
            duration: 5,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
            },
            trailing: {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            },
            onTap: {
                MediaKeyManager.requestTrust()
                if let url = MediaKeyManager.permission.settingsURL { NSWorkspace.shared.open(url) }
            }
        ).withBottom(height: 32) {
            Text("Allow Accessibility to replace the system HUD")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.84).opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        })
    }

    // MARK: Media keys

    private func handle(_ event: MediaKeyEvent) -> Bool {
        let replace = Defaults[HUDSettings.replaceSystemHUD]
        hudLog.notice("handle replace=\(replace, privacy: .public) volEnabled=\(HUDKind.volume.isEnabled, privacy: .public) canSet=\(self.volume.canSetVolume, privacy: .public) canMute=\(self.volume.canMute, privacy: .public) brightAvail=\(self.brightness.isAvailable, privacy: .public) vol=\(self.volume.volume, privacy: .public) bright=\(self.brightness.brightness, privacy: .public)")
        switch event.key {
        case .soundUp, .soundDown, .mute:
            guard replace, HUDKind.volume.isEnabled, volume.canSetVolume || volume.canMute else { return false }
            if event.isDown {
                adjustVolume(event)
            } else if event.key != .mute, volume.canSetVolume {
                playFeedbackIfNeeded(event)
            }
            return true

        case .brightnessUp, .brightnessDown:
            guard replace, HUDKind.brightness.isEnabled, brightness.isAvailable else {
                if event.isDown { brightness.noteUserIntent() }
                return false
            }
            if event.isDown { adjustBrightness(event) }
            return true

        case .illuminationUp, .illuminationDown, .illuminationToggle:
            guard HUDKind.keyboard.isEnabled, keyboard.isAvailable else { return false }
            guard replace else {
                if event.isDown { scheduleKeyboardRead() }
                return false
            }
            if event.isDown { adjustKeyboard(event) }
            return true
        }
    }

    private func adjustVolume(_ event: MediaKeyEvent) {
        if event.key == .mute {
            guard !event.isRepeat else { return }
            volume.toggleMute()
            showVolume()
            return
        }
        guard volume.canSetVolume else { return }
        let step = event.isFine ? Self.fineStep : Self.coarseStep
        let direction: Double = event.key == .soundUp ? 1 : -1
        if direction > 0, volume.isMuted {
            volume.setMuted(false)
        }
        let current = volume.isMuted ? 0 : volume.volume
        let target = Self.stepped(current, by: direction, step: step)
        volume.setVolume(target)
        if target <= 0.0001, volume.canMute, !volume.isMuted {
            volume.setMuted(true)
        }
        showVolume()
    }

    private func adjustBrightness(_ event: MediaKeyEvent) {
        let step = event.isFine ? Self.fineStep : Self.coarseStep
        let direction: Double = event.key == .brightnessUp ? 1 : -1
        let target = Self.stepped(brightness.brightness, by: direction, step: step)
        brightness.setBrightness(target, smooth: true)
        presenter.show(.brightness, value: target, symbol: HUDPresenter.brightnessSymbol(level: target))
    }

    private func adjustKeyboard(_ event: MediaKeyEvent) {
        keyboard.refresh()
        switch event.key {
        case .illuminationToggle:
            guard !event.isRepeat else { return }
            keyboard.toggle()
        default:
            let step = event.isFine ? Self.fineStep : Self.coarseStep
            let direction: Double = event.key == .illuminationUp ? 1 : -1
            keyboard.setLevel(Self.stepped(keyboard.level, by: direction, step: step))
        }
        showKeyboard()
    }

    /// When keys pass through, the system applies the change after this app sees the event.
    private func scheduleKeyboardRead() {
        pendingKeyboardRead?.cancel()
        pendingKeyboardRead = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.keyboard.refresh()
            self.showKeyboard()
        }
    }

    /// Snaps to the step grid first so mixed fine and coarse presses land on the same values as the system.
    static func stepped(_ value: Double, by direction: Double, step: Double) -> Double {
        let index = (value / step).rounded() + direction
        return min(max(index * step, 0), 1)
    }

    private func playFeedbackIfNeeded(_ event: MediaKeyEvent) {
        let enabled = (UserDefaults.standard.object(forKey: "com.apple.sound.beep.feedback") as? Int ?? 0) == 1
        // The system inverts the feedback preference while Shift alone is held.
        let invert = event.shift && !event.option
        guard enabled != invert, !volume.isMuted else { return }
        SystemSound.pop.play(volume: 1)
    }

    // MARK: Presentation

    private func showVolume() {
        let level = volume.effectiveVolume
        let symbol = HUDPresenter.volumeSymbol(level: level, muted: volume.isMuted, device: outputs.defaultDevice)
        presenter.show(.volume, value: level, symbol: symbol, dimmed: volume.isMuted)
    }

    private func showKeyboard() {
        let level = keyboard.level
        presenter.show(.keyboard, value: level, symbol: HUDPresenter.keyboardSymbol(level: level))
    }

    private func brightnessChanged(_ value: Double, userDriven: Bool) {
        guard userDriven || presenter.isVisible(.brightness) else { return }
        presenter.show(.brightness, value: value, symbol: HUDPresenter.brightnessSymbol(level: value))
    }

    private func outputChanged(_ device: AudioOutputDevice?) {
        volume.bind(to: outputs.defaultDeviceID)
        ActivityCenter.shared.dismiss(id: HUDKind.volume.activityID)
        guard let device, Defaults[HUDSettings.notifyOnOutputChange] else { return }
        presenter.showOutput(device)
    }

    private func updateBetterDisplay() {
        if Defaults[HUDSettings.betterDisplayIntegration] {
            betterDisplay.start()
        } else {
            betterDisplay.stop()
        }
    }

    private func showBetterDisplay(_ level: BetterDisplayOSD.Level) {
        switch level.kind {
        case .brightness:
            presenter.show(.brightness, value: level.value, symbol: HUDPresenter.brightnessSymbol(level: level.value))
        case .volume:
            let symbol = HUDPresenter.volumeSymbol(level: level.value, muted: level.muted, device: nil)
            presenter.show(.volume, value: level.muted ? 0 : level.value, symbol: symbol, dimmed: level.muted)
        }
    }
}
