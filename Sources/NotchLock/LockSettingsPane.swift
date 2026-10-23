import AppKit
import SwiftUI
import NotchCore

struct LockSettingsView: View {
    let weather: WeatherManager
    let onPreview: () -> Void

    @AppStorage(LockSettings.showLockActivity) private var showLockActivity
    @AppStorage(LockSettings.playSoundOnLock) private var playSoundOnLock
    @AppStorage(LockSettings.playSoundOnUnlock) private var playSoundOnUnlock
    @AppStorage(LockSettings.widgetsEnabled) private var widgetsEnabled
    @AppStorage(LockSettings.widgetStyle) private var widgetStyle
    @AppStorage(LockSettings.showMediaWidget) private var showMediaWidget
    @AppStorage(LockSettings.showWeatherWidget) private var showWeatherWidget
    @AppStorage(LockSettings.weatherStyle) private var weatherStyle
    @AppStorage(LockSettings.widgetOffset) private var widgetOffset
    @AppStorage(LockSettings.showOnScreenSaver) private var showOnScreenSaver
    @AppStorage(LockSettings.keepAwake) private var keepAwake
    @AppStorage(LockSettings.weatherUnit) private var weatherUnit
    @AppStorage(LockSettings.manualLocation) private var manualLocation
    @AppStorage(CoreSettings.showOnLockScreen) private var showOnLockScreen

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Show Lock Activity", info: "A padlock in the notch that pops open when you unlock.", isOn: $showLockActivity)
                Toggle("Play Sound on Lock", isOn: $playSoundOnLock)
                Toggle("Play Sound on Unlock", isOn: $playSoundOnUnlock)
            } header: {
                Text("Notch")
            } footer: {
                if !showOnLockScreen {
                    Text("Turn on \u{201C}Show on Lock Screen\u{201D} in General for the notch itself to appear on the lock screen.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("The notch appears on the lock screen because \u{201C}Show on Lock Screen\u{201D} is on in General.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                SettingsToggle("Lock Screen Widgets", info: "Widgets appear on the lock screen below the clock.", isOn: $widgetsEnabled)
                if widgetsEnabled {
                    Picker("Style", selection: $widgetStyle) {
                        ForEach(LockWidgetStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    SettingsToggle("Now Playing", info: "Shown while music or video is playing.", isOn: $showMediaWidget)
                    Toggle("Weather", isOn: $showWeatherWidget)
                    if showWeatherWidget {
                        Picker("Weather Style", selection: $weatherStyle) {
                            ForEach(WeatherWidgetStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    SettingsSlider("Vertical Offset", value: $widgetOffset, in: -200...200, step: 5, format: { "\(Int($0)) pt" })
                    SettingsToggle("Show on Screen Saver", info: "Keep the widgets visible while the screen saver runs.", isOn: $showOnScreenSaver)
                    SettingsToggle("Keep Awake", info: "Prevent the display from sleeping while locked and media is playing.", isOn: $keepAwake)
                    LabeledContent("Preview") {
                        Button("Show Widgets", action: onPreview)
                    }
                }
            } header: {
                Text("Widgets")
            }

            Section {
                Picker("Temperature Unit", selection: $weatherUnit) {
                    ForEach(TemperatureUnitPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Manual Location", text: $manualLocation, prompt: Text("City name, e.g. Lisbon"))
                WeatherStatusRow(weather: weather)
            } header: {
                Text("Weather")
            } footer: {
                Text("Leave Manual Location empty to use your current location. Weather data from Open-Meteo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { weather.setSettingsVisible(true) }
        .onDisappear { weather.setSettingsVisible(false) }
    }
}

private struct WeatherStatusRow: View {
    let weather: WeatherManager
    private let status = SystemStatus.shared

    var body: some View {
        LabeledContent("Status") {
            HStack(spacing: 8) {
                statusContent
                Button {
                    weather.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh Weather")
            }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch weather.state {
        case .needsLocation:
            if weather.permissionStatus == .notDetermined {
                Button("Allow Location") { Task { await weather.requestAuthorization() } }
            } else {
                Button("Open Location Settings") {
                    if let url = weather.permission.settingsURL { NSWorkspace.shared.open(url) }
                }
            }
        case .loading where status.weather == nil, .idle where status.weather == nil:
            ProgressView().controlSize(.small)
        case .failed(let message) where status.weather == nil:
            Text(message).foregroundStyle(.secondary)
        default:
            if let snapshot = status.weather {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.symbol).symbolRenderingMode(.multicolor)
                    Text("\(WeatherWidget.temperature(snapshot.temperature)) \(snapshot.conditionName)")
                    if let name = weather.locationName { Text("in \(name)") }
                    Text("\u{00B7} \(snapshot.fetchedAt, format: .dateTime.hour().minute())")
                }
                .foregroundStyle(.secondary)
            } else {
                Text("No data").foregroundStyle(.secondary)
            }
        }
    }
}
