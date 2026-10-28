import AppKit
import CoreLocation
import Observation
import NotchCore

/// Fetches local weather from Open-Meteo (WeatherKit needs a paid entitlement) and publishes it to `SystemStatus.weather`.
@MainActor
@Observable
final class WeatherManager {
    enum State: Equatable {
        case idle, loading, ready, needsLocation
        case failed(String)
    }

    private static let refreshInterval: TimeInterval = 30 * 60
    private static let locationLifetime: TimeInterval = 15 * 60
    // Owned by NotchCalendar, which this module cannot import.
    private static let calendarEnabled = SettingKey("calendar.enabled", default: true)
    private static let idleClockShowsWeather = SettingKey("nowPlaying.showIdleClock", default: true)
    private static let calendarShowsWeather = SettingKey("calendar.showWeatherOnEmptyDay", default: true)
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")

    private(set) var state: State = .idle
    /// Resolved name of the manual location, nil when using the current location.
    private(set) var locationName: String?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let delegate = LocationDelegate()
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var settingsObserver: AnyObject?
    @ObservationIgnored private var consumerObserver: AnyObject?
    @ObservationIgnored private var manualDebounce: Task<Void, Never>?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var geocodeTask: Task<Void, Never>?
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var lastFetch: (location: CLLocation, date: Date, fahrenheit: Bool)?
    @ObservationIgnored private var geocoded: (query: String, location: CLLocation, name: String)?
    @ObservationIgnored private var pendingForce = false
    @ObservationIgnored private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var isMonitoringSignificantChanges = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSettingsVisible = false
    @ObservationIgnored private var isRunning = false

    init() {
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        delegate.onAuthorizationChange = { [weak self] in self?.authorizationChanged() }
        delegate.onLocations = { [weak self] locations in self?.received(locations) }
        delegate.onError = { [weak self] in self?.locationFailed() }
        locationManager.delegate = delegate
    }

    var permissionStatus: PermissionStatus {
        switch locationManager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    var permission: PermissionRequirement {
        PermissionRequirement(
            id: "location",
            title: "Location",
            description: "Shows local weather on the lock screen.",
            symbol: "location.fill",
            settingsURL: Self.settingsURL,
            status: { [weak self] in self?.permissionStatus ?? .notDetermined },
            request: { [weak self] in await self?.requestAuthorization() }
        )
    }

    var usesManualLocation: Bool { !manualQuery.isEmpty }

    private var manualQuery: String {
        Defaults[LockSettings.manualLocation].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        consumerObserver = Defaults.observe([
            LockSettings.widgetsEnabled.name, LockSettings.showWeatherWidget.name,
            Self.calendarEnabled.name, Self.calendarShowsWeather.name, Self.idleClockShowsWeather.name,
        ]) { [weak self] in self?.updateActivity() }
        updateActivity()
    }

    func stop() {
        isStarted = false
        consumerObserver = nil
        updateActivity()
    }

    /// The settings pane shows the current weather, so it counts as a consumer while open.
    func setSettingsVisible(_ visible: Bool) {
        isSettingsVisible = visible
        updateActivity()
    }

    private var hasConsumer: Bool {
        if isSettingsVisible { return true }
        if Defaults[LockSettings.widgetsEnabled] && Defaults[LockSettings.showWeatherWidget] { return true }
        if Defaults[Self.idleClockShowsWeather] { return true }
        return Defaults[Self.calendarEnabled] && Defaults[Self.calendarShowsWeather]
    }

    private func updateActivity() {
        let wanted = isStarted && hasConsumer
        guard wanted != isRunning else { return }
        if wanted { activate() } else { deactivate() }
    }

    private func activate() {
        isRunning = true
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: true) }
        }
        refreshTimer?.tolerance = 5 * 60
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAfterWake() }
        }
        settingsObserver = Defaults.observe([LockSettings.weatherUnit.name, LockSettings.manualLocation.name]) { [weak self] in
            self?.settingsChanged()
        }
        updateSignificantChangeMonitoring()
        refresh()
    }

    private func refreshAfterWake() {
        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            // The network is usually not back the instant the Mac wakes.
            try? await Task.sleep(for: .seconds(8))
            // Unlocking right after wake usually refreshed already.
            guard !Task.isCancelled, let self, !self.fetchedRecently else { return }
            self.refresh(force: true)
        }
    }

    private var fetchedRecently: Bool {
        fetchTask != nil || lastFetch.map { Date().timeIntervalSince($0.date) < 2 * 60 } ?? false
    }

    private func deactivate() {
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        wakeTask?.cancel()
        settingsObserver = nil
        manualDebounce?.cancel()
        fetchTask?.cancel()
        fetchTask = nil
        geocodeTask?.cancel()
        updateSignificantChangeMonitoring()
        resumeAuthorizationWaiters()
    }

    func requestAuthorization() async {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            authorizationWaiters.append(continuation)
            locationManager.requestWhenInUseAuthorization()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                self?.resumeAuthorizationWaiters()
            }
        }
    }

    func refresh(force: Bool = false) {
        guard isRunning else { return }
        let query = manualQuery
        if !query.isEmpty {
            resolveManual(query)
            return
        }
        locationName = nil
        guard permissionStatus == .granted else {
            state = .needsLocation
            return
        }
        pendingForce = pendingForce || force
        if SystemStatus.shared.weather == nil { state = .loading }
        if let lastLocation, Date().timeIntervalSince(lastLocation.timestamp) < Self.locationLifetime {
            let force = pendingForce
            pendingForce = false
            fetch(for: lastLocation, force: force)
            return
        }
        locationManager.requestLocation()
    }

    // MARK: - Location

    private func settingsChanged() {
        manualDebounce?.cancel()
        manualDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.updateSignificantChangeMonitoring()
            self.refresh(force: true)
        }
    }

    private func authorizationChanged() {
        if locationManager.authorizationStatus != .notDetermined { resumeAuthorizationWaiters() }
        updateSignificantChangeMonitoring()
        refresh(force: true)
    }

    private func resumeAuthorizationWaiters() {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func updateSignificantChangeMonitoring() {
        let wanted = isRunning && permissionStatus == .granted && !usesManualLocation
        guard wanted != isMonitoringSignificantChanges else { return }
        isMonitoringSignificantChanges = wanted
        if wanted {
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    private func received(_ locations: [CLLocation]) {
        guard let location = locations.last, !usesManualLocation else { return }
        lastLocation = location
        guard isRunning else { return }
        let force = pendingForce
        pendingForce = false
        fetch(for: location, force: force)
    }

    private func locationFailed() {
        guard isRunning, !usesManualLocation else { return }
        let force = pendingForce
        pendingForce = false
        if let lastLocation {
            fetch(for: lastLocation, force: force)
        } else if SystemStatus.shared.weather == nil {
            state = .failed("Your location is unavailable. Try entering a city.")
        }
    }

    private func resolveManual(_ query: String) {
        if let geocoded, geocoded.query == query {
            locationName = geocoded.name
            fetch(for: geocoded.location, force: true)
            return
        }
        geocodeTask?.cancel()
        state = .loading
        geocodeTask = Task { [weak self] in
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(query)
                guard !Task.isCancelled, let self, self.manualQuery == query else { return }
                guard let placemark = placemarks.first, let location = placemark.location else {
                    self.state = .failed("Couldn't find \u{201C}\(query)\u{201D}.")
                    return
                }
                let name = placemark.locality ?? placemark.name ?? query
                self.geocoded = (query, location, name)
                self.locationName = name
                self.fetch(for: location, force: true)
            } catch {
                guard !Task.isCancelled, let self, self.manualQuery == query else { return }
                self.state = .failed("Couldn't find \u{201C}\(query)\u{201D}.")
            }
        }
    }

    // MARK: - Fetching

    private func fetch(for location: CLLocation, force: Bool) {
        let fahrenheit = Defaults[LockSettings.weatherUnit].usesFahrenheit
        if !force, let lastFetch, lastFetch.fahrenheit == fahrenheit,
           lastFetch.location.distance(from: location) < 3000,
           Date().timeIntervalSince(lastFetch.date) < 10 * 60 {
            return
        }
        fetchTask?.cancel()
        if SystemStatus.shared.weather == nil { state = .loading }
        let coordinate = location.coordinate
        fetchTask = Task { [weak self] in
            do {
                let snapshot = try await OpenMeteo.forecast(
                    latitude: coordinate.latitude, longitude: coordinate.longitude, fahrenheit: fahrenheit
                )
                guard !Task.isCancelled, let self else { return }
                SystemStatus.shared.weather = snapshot
                self.lastFetch = (location, Date(), fahrenheit)
                self.fetchTask = nil
                self.state = .ready
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.fetchTask = nil
                self.state = .failed("Weather is unavailable right now.")
            }
        }
    }
}

/// CoreLocation calls back on the thread that created the manager, which is the main thread here.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onAuthorizationChange: (@MainActor () -> Void)?
    var onLocations: (@MainActor ([CLLocation]) -> Void)?
    var onError: (@MainActor () -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { onAuthorizationChange?() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { onLocations?(locations) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { onError?() }
    }
}

enum OpenMeteo {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature: Double
            let weatherCode: Int
            let isDay: Int

            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let high: [Double?]
            let low: [Double?]
            let precipitation: [Double?]
            let sunrise: [String]
            let sunset: [String]

            enum CodingKeys: String, CodingKey {
                case high = "temperature_2m_max"
                case low = "temperature_2m_min"
                case precipitation = "precipitation_probability_max"
                case sunrise, sunset
            }
        }

        let utcOffsetSeconds: Int?
        let current: Current
        let daily: Daily

        enum CodingKeys: String, CodingKey {
            case utcOffsetSeconds = "utc_offset_seconds"
            case current, daily
        }
    }

    static func forecast(latitude: Double, longitude: Double, fahrenheit: Bool) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        if fahrenheit { items.append(URLQueryItem(name: "temperature_unit", value: "fahrenheit")) }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // Open-Meteo returns sunrise and sunset as local wall-clock times in the forecast location's zone.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = decoded.utcOffsetSeconds.flatMap(TimeZone.init(secondsFromGMT:)) ?? .current

        let current = decoded.current
        let daily = decoded.daily
        let condition = WeatherCode.condition(for: current.weatherCode)
        return WeatherSnapshot(
            temperature: current.temperature,
            high: daily.high.first.flatMap { $0 } ?? current.temperature,
            low: daily.low.first.flatMap { $0 } ?? current.temperature,
            conditionName: condition.name,
            symbol: condition.symbol(isDay: current.isDay != 0),
            precipitationChance: (daily.precipitation.first.flatMap { $0 } ?? 0) / 100,
            sunrise: daily.sunrise.first.flatMap(formatter.date(from:)),
            sunset: daily.sunset.first.flatMap(formatter.date(from:)),
            unitSymbol: fahrenheit ? "°F" : "°C",
            fetchedAt: Date()
        )
    }
}
