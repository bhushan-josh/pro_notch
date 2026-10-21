import EventKit
import NotchCore
import SwiftUI

struct CalendarSettingsView: View {
    let timeToLeave: TimeToLeave
    private let manager = CalendarManager.shared

    @AppStorage(CalendarSettings.enabled) private var enabled
    @AppStorage(CalendarSettings.alwaysShowMonthView) private var alwaysShowMonthView
    @AppStorage(CalendarSettings.useEventIndicators) private var useEventIndicators
    @AppStorage(CalendarSettings.useCalendarColor) private var useCalendarColor
    @AppStorage(CalendarSettings.showWeatherOnEmptyDay) private var showWeatherOnEmptyDay
    @AppStorage(CalendarSettings.notifyBeforeEvent) private var notifyBeforeEvent
    @AppStorage(CalendarSettings.timeBeforeEvent) private var timeBeforeEvent
    @AppStorage(CalendarSettings.notifyWhenEventStarts) private var notifyWhenEventStarts
    @AppStorage(CalendarSettings.disableActivityDuringEvents) private var disableActivityDuringEvents
    @AppStorage(CalendarSettings.useColoredCalendarIndicator) private var useColoredCalendarIndicator
    @AppStorage(CalendarSettings.playSoundOnEvent) private var playSoundOnEvent
    @AppStorage(CalendarSettings.notifyWhenTimeToLeave) private var notifyWhenTimeToLeave
    @AppStorage(CalendarSettings.transport) private var transport
    @AppStorage(CalendarSettings.timeToLeaveBuffer) private var timeToLeaveBuffer
    @AppStorage(CalendarSettings.timeToLeaveDuration) private var timeToLeaveDuration
    @AppStorage(CalendarSettings.playSoundOnNotification) private var playSoundOnNotification
    @AppStorage(CalendarSettings.playHourlyChime) private var playHourlyChime

    @State private var locationStatus: PermissionStatus = .notDetermined

    private static let leadTimes = [1, 2, 5, 10, 15, 30, 60]
    private static let buffers = [0, 5, 10, 15, 20, 30]

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Enable Calendar", info: "Show your events on the Home page and in the notch.", isOn: $enabled)
                if manager.authorization != .granted {
                    LabeledContent("Calendar Access") {
                        Button(manager.authorization == .notDetermined ? "Allow Access" : "Open System Settings") {
                            Task { await manager.requestAccess() }
                        }
                    }
                }
            }

            if manager.authorization == .granted {
                ForEach(manager.calendarGroups) { group in
                    Section(group.title) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                            Toggle(isOn: Binding(
                                get: { manager.isSelected(cal) },
                                set: { manager.setSelected(cal, $0) }
                            )) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: cal.color ?? .systemRed))
                                        .frame(width: 10, height: 10)
                                    Text(cal.title)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            Section("Home") {
                SettingsToggle("Always Show Month View", info: "Replace the week strip with a compact month.", isOn: $alwaysShowMonthView)
                SettingsToggle("Event Indicators", info: "Show a dot under days that have events.", isOn: $useEventIndicators)
                SettingsToggle("Use Calendar Colors", info: "Tint events with their calendar's color.", isOn: $useCalendarColor)
                SettingsToggle("Show Weather on Empty Days", info: "Shows the current weather when today has nothing left.", isOn: $showWeatherOnEmptyDay)
            }

            Section("Notch Activities") {
                Toggle("Before Event Starts", isOn: $notifyBeforeEvent)
                if notifyBeforeEvent {
                    Picker("Time Before Event", selection: $timeBeforeEvent) {
                        ForEach(Self.leadTimes, id: \.self) { Text(Self.minutes($0)).tag($0) }
                    }
                }
                Toggle("When Event Is Starting", isOn: $notifyWhenEventStarts)
                SettingsToggle("Hide Activity During Events", info: "Do not show the ongoing event in the closed notch.", isOn: $disableActivityDuringEvents)
                SettingsToggle("Colored Calendar Indicator", info: "Use the calendar's color instead of a calendar symbol.", isOn: $useColoredCalendarIndicator)
                Toggle("Play Sound on Event", isOn: $playSoundOnEvent)
            }

            Section("Time to Leave") {
                SettingsToggle("Notify When It's Time to Leave", info: "Uses your location and Apple Maps travel time for events with an address.", isOn: $notifyWhenTimeToLeave)
                if notifyWhenTimeToLeave {
                    Picker("Transport", selection: $transport) {
                        ForEach(CalendarTransport.allCases, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    Picker("Extra Buffer", selection: $timeToLeaveBuffer) {
                        ForEach(Self.buffers, id: \.self) { Text($0 == 0 ? "None" : Self.minutes($0)).tag($0) }
                    }
                    SettingsSlider("Alert Duration", value: $timeToLeaveDuration, in: 3...30, step: 1, format: { String(format: "%.0fs", $0) })
                    Toggle("Play Sound on Notification", isOn: $playSoundOnNotification)
                    if locationStatus != .granted {
                        LabeledContent("Location Access") {
                            Button(locationStatus == .notDetermined ? "Allow Access" : "Open System Settings") {
                                timeToLeave.requestAuthorization()
                            }
                        }
                    }
                }
            }

            Section("Chime") {
                SettingsToggle("Play Hourly Chime", info: "A soft chime and the time at the top of every hour.", isOn: $playHourlyChime)
            }
        }
        .onAppear {
            manager.revalidate()
            locationStatus = timeToLeave.locationStatus
        }
        .onChange(of: notifyWhenTimeToLeave) {
            locationStatus = timeToLeave.locationStatus
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.revalidate()
            locationStatus = timeToLeave.locationStatus
        }
    }

    private static func minutes(_ value: Int) -> String {
        value == 60 ? "1 hour" : value == 1 ? "1 minute" : "\(value) minutes"
    }
}
