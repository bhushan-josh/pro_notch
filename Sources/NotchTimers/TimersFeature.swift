import AppKit
import NotchCore
import SwiftUI

@MainActor
public final class TimersFeature: NotchFeature {
    public static let pageID = "timers"
    static let activeActivityID = "timers.active"
    static let doneActivityID = "timers.done"
    static let lockWidgetID = "timer"

    private let manager = TimerManager()
    private var settingsObserver: AnyObject?
    private var wakeObserver: NSObjectProtocol?

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        let manager = manager
        registry.register(settingsPane: SettingsPane(id: "timers", title: "Timers", symbol: "timer", color: .orange, category: .liveActivities, order: 65) {
            TimersSettingsView()
        })
        updatePage()

        manager.onChange = { [weak self] in self?.refresh() }
        manager.onFinish = { [weak self] in self?.finished() }
        manager.restore()
        refresh()

        settingsObserver = Defaults.observe([
            TimersSettings.showTab.name, TimersSettings.showInNotch.name, TimersSettings.showOnLockScreen.name, TimersSettings.presets.name,
        ]) { [weak self] in
            guard let self else { return }
            self.updatePage()
            let presets = TimersSettings.presetMinutes
            if self.manager.presets != presets { self.manager.presets = presets }
            self.refresh()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.manager.revalidate() }
        }
    }

    public func stop() {
        manager.suspend()
        manager.onChange = nil
        manager.onFinish = nil
        settingsObserver = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        removePage()
        NotchRegistry.shared.unregister(lockScreenWidgetID: Self.lockWidgetID)
        ActivityCenter.shared.dismiss(id: Self.activeActivityID)
        ActivityCenter.shared.dismiss(id: Self.doneActivityID)
    }

    private func updatePage() {
        let registry = NotchRegistry.shared
        guard Defaults[TimersSettings.showTab] else { return removePage() }
        guard !registry.pages.contains(where: { $0.id == Self.pageID }) else { return }
        let manager = manager
        registry.register(page: NotchPage(id: Self.pageID, title: "Timers", symbol: "timer", order: 40) {
            TimersPage(manager: manager)
        })
    }

    private func removePage() {
        for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
            model.selectedPageID = NotchModel.homePageID
        }
        NotchRegistry.shared.unregister(pageID: Self.pageID)
    }

    private func refresh() {
        let center = ActivityCenter.shared
        switch manager.phase {
        case .running, .paused:
            center.dismiss(id: Self.doneActivityID)
            if Defaults[TimersSettings.showInNotch] {
                center.present(activeActivity())
            } else {
                center.dismiss(id: Self.activeActivityID)
            }
        case .finished:
            center.dismiss(id: Self.activeActivityID)
        case .idle:
            center.dismiss(id: Self.activeActivityID)
            center.dismiss(id: Self.doneActivityID)
        }
        updateLockScreenWidget()
    }

    /// Re-presented on every state change; the same id updates in place.
    private func activeActivity() -> LiveActivity {
        let manager = manager
        let showsHours = manager.remaining() >= 3600
        return LiveActivity(
            id: Self.activeActivityID,
            category: .other,
            priority: .normal,
            duration: nil,
            leadingWidth: 22,
            trailingWidth: showsHours ? 54 : 40,
            leading: { TimerLeadingWing(manager: manager) },
            trailing: { TimerTrailingWing(manager: manager) },
            onTap: { NotchManager.shared.activeModel?.open(page: TimersFeature.pageID) }
        )
    }

    private func finished() {
        let manager = manager
        Haptics.perform(.levelChange)
        ActivityCenter.shared.present(LiveActivity(
            id: Self.doneActivityID,
            category: .other,
            priority: .high,
            duration: TimerManager.alertDuration,
            leadingWidth: 28,
            trailingWidth: 28,
            leading: { TimerDoneLeading() },
            trailing: { TimerDoneTrailing() },
            onTap: { NotchManager.shared.activeModel?.open(page: TimersFeature.pageID) }
        ).withBottom(height: 38) { TimerDoneStrip(manager: manager) })
        manager.ring(activityID: Self.doneActivityID)
    }

    private func updateLockScreenWidget() {
        let registry = NotchRegistry.shared
        let wanted = manager.phase != .idle && Defaults[TimersSettings.showOnLockScreen]
        let registered = registry.lockScreenWidgets.contains { $0.id == Self.lockWidgetID }
        if wanted, !registered {
            let manager = manager
            registry.register(lockScreenWidget: LockScreenWidget(id: Self.lockWidgetID, order: 5) {
                TimerLockScreenView(manager: manager)
            })
        } else if !wanted, registered {
            registry.unregister(lockScreenWidgetID: Self.lockWidgetID)
        }
    }
}
