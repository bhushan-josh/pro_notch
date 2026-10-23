import AppKit
import EventKit
import NotchCore
import Observation
import SwiftUI

@MainActor
@Observable
final class CalendarManager {
    static let shared = CalendarManager()

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    private static let noneSelected = "none"

    @ObservationIgnored let store = EKEventStore()

    private(set) var authorization: PermissionStatus = .notDetermined
    /// Advanced once a minute; views read it so countdowns and "past event" filtering stay current.
    private(set) var now = Date()
    private(set) var eventsByDay: [Date: [CalendarEvent]] = [:]
    private(set) var calendars: [EKCalendar] = []
    private(set) var dismissedIDs: Set<String> = []
    private(set) var selectedCalendarIDs = Defaults[CalendarSettings.selectedCalendarIDs]
    private(set) var isRunning = false

    var selectedDay: Date {
        didSet {
            let day = calendar.startOfDay(for: selectedDay)
            if day != selectedDay { selectedDay = day }
            if isRunning, !isFetched(day) { fetch() }
        }
    }

    /// Called after every minute tick and every refetch.
    @ObservationIgnored var onUpdate: (@MainActor () -> Void)?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var settingsObserver: AnyObject?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var fetchedRange: DateInterval?
    @ObservationIgnored private var currentDay: Date
    @ObservationIgnored private var timeZone = TimeZone.current

    private var calendar: Calendar { .current }

    private init() {
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
        currentDay = today
        loadDismissed()
        refreshAuthorizationStatus()
    }

    var today: Date { calendar.startOfDay(for: now) }
    var tomorrow: Date { calendar.addingDays(1, to: today) }

    func events(on day: Date) -> [CalendarEvent] {
        eventsByDay[calendar.startOfDay(for: day)] ?? []
    }

    func hasEvents(on day: Date) -> Bool {
        !(eventsByDay[calendar.startOfDay(for: day)]?.isEmpty ?? true)
    }

    /// Timed events of today and tomorrow that have not ended, de-duplicated across days.
    var upcomingTimedEvents: [CalendarEvent] {
        var seen = Set<String>()
        return (events(on: today) + events(on: tomorrow))
            .filter { !$0.isAllDay && !$0.hasEnded(at: now) && seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    func isDismissed(_ event: CalendarEvent) -> Bool { dismissedIDs.contains(event.id) }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.storeChanged() }
            },
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clockChanged() }
            },
            center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clockChanged() }
            },
        ]
        workspaceObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
        settingsObserver = Defaults.observe([CalendarSettings.selectedCalendarIDs.name]) { [weak self] in
            guard let self else { return }
            self.selectedCalendarIDs = Defaults[CalendarSettings.selectedCalendarIDs]
            self.fetch()
        }
        refresh()
        startTicking()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        workspaceObservers = []
        settingsObserver = nil
        tickTask?.cancel()
        tickTask = nil
        eventsByDay = [:]
        fetchedRange = nil
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let reference = Date().timeIntervalSinceReferenceDate
                let nextMinute = (reference / 60).rounded(.down) * 60 + 60.25
                try? await Task.sleep(for: .seconds(nextMinute - reference))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        now = Date()
        let day = calendar.startOfDay(for: now)
        if day != currentDay {
            let wasShowingToday = selectedDay == currentDay
            currentDay = day
            loadDismissed()
            fetchedRange = nil
            if wasShowingToday { selectedDay = day }
            if fetchedRange == nil { fetch() }
            return
        }
        onUpdate?()
    }

    /// Moves a non-today `selectedDay` to the same calendar date at midnight in the new time zone.
    private func clockChanged() {
        var previous = calendar
        previous.timeZone = timeZone
        timeZone = calendar.timeZone
        if selectedDay != currentDay,
           let day = calendar.date(from: previous.dateComponents([.year, .month, .day], from: selectedDay)),
           day != selectedDay {
            selectedDay = day
        }
        refresh()
    }

    func refresh() {
        now = Date()
        refreshAuthorizationStatus()
        tick()
        fetch()
    }

    private func storeChanged() {
        reloadCalendars()
        fetch()
    }

    // MARK: Authorization

    func refreshAuthorizationStatus() {
        let status: PermissionStatus = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
        guard status != authorization || calendars.isEmpty else { return }
        authorization = status
        reloadCalendars()
    }

    /// Picks up access granted in System Settings while the app was running.
    func revalidate() {
        let before = authorization
        refreshAuthorizationStatus()
        if before != authorization { fetch() }
    }

    func requestAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        } else if authorization != .granted, let url = Self.privacySettingsURL {
            NSWorkspace.shared.open(url)
        }
        refreshAuthorizationStatus()
        fetch()
    }

    var permission: PermissionRequirement {
        PermissionRequirement(
            id: "calendar",
            title: "Calendar",
            description: "Show upcoming events and remind you before they start.",
            symbol: "calendar",
            settingsURL: Self.privacySettingsURL,
            status: {
                switch EKEventStore.authorizationStatus(for: .event) {
                case .fullAccess: .granted
                case .notDetermined: .notDetermined
                default: .denied
                }
            },
            request: { await CalendarManager.shared.requestAccess() }
        )
    }

    // MARK: Calendars

    private func reloadCalendars() {
        calendars = authorization == .granted ? store.calendars(for: .event) : []
    }

    /// Nil means all calendars.
    private var selectedCalendars: [EKCalendar]? {
        let ids = Set(selectedCalendarIDs)
        guard !ids.isEmpty else { return nil }
        return calendars.filter { ids.contains($0.calendarIdentifier) }
    }

    func isSelected(_ cal: EKCalendar) -> Bool {
        selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains(cal.calendarIdentifier)
    }

    func setSelected(_ cal: EKCalendar, _ selected: Bool) {
        let all = calendars.map(\.calendarIdentifier)
        var ids = Set(selectedCalendarIDs)
        if ids.isEmpty { ids = Set(all) }
        ids.remove(Self.noneSelected)
        if selected { ids.insert(cal.calendarIdentifier) } else { ids.remove(cal.calendarIdentifier) }
        if ids.isSuperset(of: all) {
            selectedCalendarIDs = []
        } else if ids.isEmpty {
            selectedCalendarIDs = [Self.noneSelected]
        } else {
            selectedCalendarIDs = all.filter(ids.contains)
        }
        Defaults[CalendarSettings.selectedCalendarIDs] = selectedCalendarIDs
    }

    struct CalendarGroup: Identifiable {
        let id: String
        let title: String
        let calendars: [EKCalendar]
    }

    /// Calendars grouped by account, with subscribed calendars collected under "Subscribed".
    var calendarGroups: [CalendarGroup] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var members: [String: [EKCalendar]] = [:]
        for cal in calendars.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            let key: String
            let title: String
            if cal.type == .subscription || cal.source?.sourceType == .subscribed {
                (key, title) = ("~subscribed", "Subscribed")
            } else if cal.type == .birthday {
                (key, title) = ("~other", "Other")
            } else {
                (key, title) = (cal.source?.sourceIdentifier ?? "~local", cal.source?.title ?? "On My Mac")
            }
            if members[key] == nil { order.append(key) }
            titles[key] = title
            members[key, default: []].append(cal)
        }
        let rank: (String) -> Int = { key in key == "~subscribed" ? 2 : key == "~other" ? 1 : 0 }
        return order
            .enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map { CalendarGroup(id: $0.element, title: titles[$0.element] ?? "", calendars: members[$0.element] ?? []) }
    }

    // MARK: Fetching

    private func fetchInterval(for day: Date) -> DateInterval {
        let gridStart = calendar.monthGridStart(for: day)
        let gridEnd = calendar.addingDays(42, to: gridStart)
        let start = min(gridStart, today)
        let end = max(gridEnd, calendar.addingDays(2, to: today))
        return DateInterval(start: start, end: end)
    }

    private func isFetched(_ day: Date) -> Bool {
        guard let fetchedRange else { return false }
        let wanted = fetchInterval(for: day)
        return fetchedRange.start <= wanted.start && fetchedRange.end >= wanted.end
    }

    func fetch() {
        guard isRunning, authorization == .granted else {
            eventsByDay = [:]
            fetchedRange = nil
            onUpdate?()
            return
        }
        let interval = fetchInterval(for: selectedDay)
        let chosen = selectedCalendars
        var grouped: [Date: [CalendarEvent]] = [:]
        if chosen?.isEmpty != true {
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: chosen)
            for ekEvent in store.events(matching: predicate) where Self.shouldShow(ekEvent) {
                let event = CalendarEvent(ekEvent)
                var day = max(calendar.startOfDay(for: event.start), interval.start)
                repeat {
                    grouped[day, default: []].append(event)
                    day = calendar.addingDays(1, to: day)
                } while day < event.end && day < interval.end
            }
        }
        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start == rhs.start ? lhs.title < rhs.title : lhs.start < rhs.start
            }
        }
        fetchedRange = interval
        if grouped != eventsByDay { eventsByDay = grouped }
        onUpdate?()
    }

    private static func shouldShow(_ event: EKEvent) -> Bool {
        if event.status == .canceled { return false }
        if let me = event.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return false }
        return true
    }

    // MARK: Dismissed events

    private static func dayStamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    private func loadDismissed() {
        if Defaults[CalendarSettings.dismissedDay] == Self.dayStamp(Date()) {
            dismissedIDs = Set(Defaults[CalendarSettings.dismissedEventIDs])
        } else {
            dismissedIDs = []
            Defaults[CalendarSettings.dismissedEventIDs] = []
            Defaults[CalendarSettings.dismissedDay] = Self.dayStamp(Date())
        }
    }

    func dismiss(_ event: CalendarEvent) {
        dismissedIDs.insert(event.id)
        Defaults[CalendarSettings.dismissedDay] = Self.dayStamp(Date())
        Defaults[CalendarSettings.dismissedEventIDs] = Array(dismissedIDs)
        CalendarActivityID.all(for: event).forEach { ActivityCenter.shared.dismiss(id: $0) }
        onUpdate?()
    }

    func restore(_ event: CalendarEvent) {
        dismissedIDs.remove(event.id)
        Defaults[CalendarSettings.dismissedEventIDs] = Array(dismissedIDs)
        onUpdate?()
    }

    // MARK: Actions

    static func open(_ event: CalendarEvent) {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~:"))
        let encoded = event.eventIdentifier.addingPercentEncoding(withAllowedCharacters: allowed) ?? event.eventIdentifier
        if let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"), NSWorkspace.shared.open(url) {
            NotchManager.shared.closeAll()
            return
        }
        openCalendarApp()
    }

    static func openCalendarApp() {
        NotchManager.shared.closeAll()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func join(_ event: CalendarEvent) {
        guard let link = event.meeting else { return open(event) }
        NotchManager.shared.closeAll()
        NSWorkspace.shared.open(link.url)
    }
}
