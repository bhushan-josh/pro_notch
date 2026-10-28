import NotchCore
import SwiftUI

@MainActor
public final class CalendarFeature: NotchFeature {
    public static let pageID = "calendar"

    private let manager = CalendarManager.shared
    private let activities: CalendarActivities
    private let timeToLeave: TimeToLeave
    private var settingsObserver: AnyObject?
    private var widgetRegistered = false

    public init() {
        activities = CalendarActivities(manager: manager)
        timeToLeave = TimeToLeave(manager: manager)
    }

    public func start() {
        let registry = NotchRegistry.shared
        let timeToLeave = timeToLeave
        registry.register(settingsPane: SettingsPane(id: "calendar", title: "Calendar", symbol: "calendar", color: .red, category: .liveActivities, order: 60) {
            CalendarSettingsView(timeToLeave: timeToLeave)
        })
        registry.register(permission: manager.permission)
        registry.register(idleProvider: activities)

        manager.onUpdate = { [weak self] in
            self?.activities.update()
            self?.timeToLeave.update()
        }
        timeToLeave.start()
        settingsObserver = Defaults.observe([
            CalendarSettings.enabled.name,
            CalendarSettings.notifyBeforeEvent.name,
            CalendarSettings.timeBeforeEvent.name,
            CalendarSettings.notifyWhenEventStarts.name,
            CalendarSettings.disableActivityDuringEvents.name,
            CalendarSettings.useColoredCalendarIndicator.name,
            CalendarSettings.playHourlyChime.name,
        ]) { [weak self] in self?.apply() }
        apply()
    }

    public func stop() {
        settingsObserver = nil
        manager.onUpdate = nil
        manager.stop()
        timeToLeave.stop()
        activities.stop()
        if widgetRegistered {
            NotchRegistry.shared.unregister(homeWidgetID: "calendar")
            widgetRegistered = false
        }
        removePage()
    }

    private func apply() {
        let registry = NotchRegistry.shared
        if Defaults[CalendarSettings.enabled] {
            if !widgetRegistered {
                registry.register(homeWidget: HomeWidget(id: "calendar", kind: .calendar) { CalendarWidget() })
                widgetRegistered = true
            }
            if !registry.pages.contains(where: { $0.id == Self.pageID }) {
                registry.register(page: NotchPage(
                    id: Self.pageID,
                    title: "Calendar",
                    symbol: "calendar",
                    order: 45,
                    resize: PageResize(minSize: CGSize(width: 375, height: 180), maxSize: CGSize(width: 640, height: 480))
                ) {
                    CalendarWidget(forceMonthView: true)
                })
            }
            manager.start()
            activities.update()
        } else {
            if widgetRegistered {
                registry.unregister(homeWidgetID: "calendar")
                widgetRegistered = false
            }
            removePage()
            manager.stop()
            activities.stop()
        }
    }

    private func removePage() {
        for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
            model.selectedPageID = NotchModel.homePageID
        }
        NotchRegistry.shared.unregister(pageID: Self.pageID)
    }
}
