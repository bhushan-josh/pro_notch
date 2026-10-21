import AppKit
import CoreLocation
import MapKit
import NotchCore
import SwiftUI

/// Estimates travel time to upcoming events with a physical location and says when to leave.
@MainActor
final class TimeToLeave: NSObject, CLLocationManagerDelegate {
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")

    private struct Estimate {
        var travelTime: TimeInterval?
        var destination: MKMapItem?
        var transport: CalendarTransport
        var computedAt: Date
    }

    private let manager: CalendarManager
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastLocationRequest: Date?
    private var estimates: [String: Estimate] = [:]
    private var geocoded: [String: MKMapItem?] = [:]
    private var inFlight: Set<String> = []
    private var notified: Set<String> = []
    private var permissionRegistered = false
    private var settingsObserver: AnyObject?

    private static let estimateLifetime: TimeInterval = 10 * 60
    private static let horizon: TimeInterval = 4 * 3600

    init(manager: CalendarManager) {
        self.manager = manager
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isEnabled: Bool {
        Defaults[CalendarSettings.enabled] && Defaults[CalendarSettings.notifyWhenTimeToLeave]
    }

    func start() {
        settingsObserver = Defaults.observe([
            CalendarSettings.enabled.name,
            CalendarSettings.notifyWhenTimeToLeave.name,
            CalendarSettings.transport.name,
            CalendarSettings.timeToLeaveBuffer.name,
        ]) { [weak self] in self?.settingsChanged() }
        settingsChanged()
    }

    func stop() {
        settingsObserver = nil
        estimates = [:]
        inFlight = []
    }

    private func settingsChanged() {
        estimates = estimates.filter { $0.value.transport == Defaults[CalendarSettings.transport] }
        if isEnabled {
            registerPermission()
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }
        update()
    }

    // MARK: Permission

    static func status(of manager: CLLocationManager) -> PermissionStatus {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    var locationStatus: PermissionStatus { Self.status(of: locationManager) }

    private func registerPermission() {
        guard !permissionRegistered else { return }
        permissionRegistered = true
        NotchRegistry.shared.register(permission: PermissionRequirement(
            id: "location",
            title: "Location",
            description: "Estimate travel time to events and tell you when to leave.",
            symbol: "location.fill",
            settingsURL: Self.privacySettingsURL,
            status: { [weak self] in self?.locationStatus ?? .notDetermined },
            request: { [weak self] in self?.requestAuthorization() }
        ))
    }

    func requestAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let url = Self.privacySettingsURL { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    // MARK: Scheduling

    func update() {
        guard isEnabled, locationStatus == .granted else { return }
        let now = Date()
        let candidates = manager.upcomingTimedEvents.filter { event in
            let until = event.start.timeIntervalSince(now)
            return until > 0 && until <= Self.horizon && !manager.isDismissed(event)
                && (event.coordinate != nil || event.travelDestination != nil)
        }
        notified.formIntersection(Set(candidates.map(\.id)))
        guard !candidates.isEmpty else { return }

        requestLocationIfStale(now)
        guard let origin = lastLocation else { return }

        let transport = Defaults[CalendarSettings.transport]
        let buffer = TimeInterval(max(0, Defaults[CalendarSettings.timeToLeaveBuffer])) * 60
        for event in candidates {
            if let estimate = estimates[event.id], estimate.transport == transport,
               now.timeIntervalSince(estimate.computedAt) < Self.estimateLifetime {
                guard let travelTime = estimate.travelTime else { continue }
                let leaveAt = event.start.addingTimeInterval(-travelTime - buffer)
                if now >= leaveAt, notified.insert(event.id).inserted {
                    presentLeaveNow(event, travelTime: travelTime, destination: estimate.destination, transport: transport)
                }
            } else if inFlight.insert(event.id).inserted {
                Task { [weak self] in
                    guard let self else { return }
                    let estimate = await self.estimate(event, from: origin, transport: transport)
                    self.inFlight.remove(event.id)
                    self.estimates[event.id] = estimate
                    if estimate.travelTime != nil { self.update() }
                }
            }
        }
    }

    private func requestLocationIfStale(_ now: Date) {
        let fresh = lastLocation.map { now.timeIntervalSince($0.timestamp) < 15 * 60 } ?? false
        let recentlyAsked = lastLocationRequest.map { now.timeIntervalSince($0) < 60 } ?? false
        guard !fresh, !recentlyAsked else { return }
        lastLocationRequest = now
        locationManager.requestLocation()
    }

    // MARK: Estimating

    private func estimate(_ event: CalendarEvent, from origin: CLLocation, transport: CalendarTransport) async -> Estimate {
        var estimate = Estimate(travelTime: nil, destination: nil, transport: transport, computedAt: Date())
        guard let destination = await destination(for: event, near: origin) else { return estimate }
        estimate.destination = destination
        let request = MKDirections.Request()
        request.source = Self.mapItem(for: origin)
        request.destination = destination
        request.transportType = transport.directionsType
        request.departureDate = Date()
        if let response = try? await MKDirections(request: request).calculateETA() {
            estimate.travelTime = response.expectedTravelTime
        }
        return estimate
    }

    private func destination(for event: CalendarEvent, near origin: CLLocation) async -> MKMapItem? {
        if let coordinate = event.coordinate {
            let item = Self.mapItem(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            item.name = event.location ?? event.title
            return item
        }
        guard let address = event.travelDestination else { return nil }
        if let cached = geocoded[address] { return cached }
        let region = MKCoordinateRegion(center: origin.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000)
        var item: MKMapItem?
        if #available(macOS 26, *) {
            if let request = MKGeocodingRequest(addressString: address) {
                request.region = region
                item = try? await request.mapItems.first
            }
        }
        if item == nil {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = address
            search.region = region
            item = try? await MKLocalSearch(request: search).start().mapItems.first
        }
        geocoded[address] = item
        return item
    }

    private static func mapItem(for location: CLLocation) -> MKMapItem {
        if #available(macOS 26, *) {
            return MKMapItem(location: location, address: nil)
        }
        return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
    }

    // MARK: Presenting

    private func presentLeaveNow(_ event: CalendarEvent, travelTime: TimeInterval, destination: MKMapItem?, transport: CalendarTransport) {
        let colored = Defaults[CalendarSettings.useColoredCalendarIndicator]
        let tint = colored ? event.calendarColor : .white
        let activity = LiveActivity(
            id: CalendarActivityID.leave(event),
            category: .calendar,
            priority: .high,
            duration: max(3, Defaults[CalendarSettings.timeToLeaveDuration]),
            leadingWidth: 26,
            trailingWidth: 54,
            leading: {
                Image(systemName: transport.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            },
            trailing: {
                Text(EventFormat.duration(travelTime))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            },
            onTap: { Self.openDirections(to: destination, transport: transport, fallback: event) }
        )
        .withBottom(height: 24) {
            HStack(spacing: 6) {
                Text("Leave now")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .fixedSize()
                MarqueeText(event.title, font: .system(size: 12, weight: .semibold))
            }
        }
        ActivityCenter.shared.present(activity)
        if Defaults[CalendarSettings.playSoundOnNotification] { SystemSound.notification.play() }
    }

    private static func openDirections(to destination: MKMapItem?, transport: CalendarTransport, fallback event: CalendarEvent) {
        guard let destination else { return CalendarManager.open(event) }
        let mode = switch transport {
        case .drive: MKLaunchOptionsDirectionsModeDriving
        case .walk: MKLaunchOptionsDirectionsModeWalking
        case .transit: MKLaunchOptionsDirectionsModeTransit
        }
        NotchManager.shared.closeAll()
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            lastLocation = location
            update()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { update() }
    }
}
