import SwiftUI
import Observation

@MainActor
@Observable
public final class ActivityCenter {
    public static let shared = ActivityCenter()

    private struct Entry {
        var activity: LiveActivity
        var presentedAt: Date
        var generation: Int
    }

    private var entries: [String: Entry] = [:]
    private var generation = 0
    private var idleOffset = 0

    /// Return false to drop an activity before it is shown (Focus modes use this to silence categories).
    @ObservationIgnored public var gate: ((LiveActivity) -> Bool)?

    private init() {}

    public var transientActivities: [LiveActivity] {
        entries.values
            .sorted { ($0.activity.priority, $0.presentedAt) > ($1.activity.priority, $1.presentedAt) }
            .map(\.activity)
    }

    public var idleActivities: [LiveActivity] {
        let providers = NotchRegistry.shared.idleProviders
        let ordered = Defaults[CoreSettings.idleMostRecent]
            ? providers.sorted { $0.idleActivityUpdatedAt > $1.idleActivityUpdatedAt }
            : providers
        return ordered.compactMap(\.idleActivity)
    }

    /// The activity the closed notch should render right now, transient first.
    public var current: LiveActivity? {
        if let top = transientActivities.first { return top }
        let idle = idleActivities
        guard !idle.isEmpty else { return nil }
        return idle[((idleOffset % idle.count) + idle.count) % idle.count]
    }

    public func present(_ activity: LiveActivity) {
        if let gate, !gate(activity) { return }
        generation += 1
        let gen = generation
        let presentedAt = entries[activity.id]?.presentedAt ?? Date()
        withAnimation(.notchSpring) {
            entries[activity.id] = Entry(activity: activity, presentedAt: presentedAt, generation: gen)
        }
        guard let duration = activity.duration else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, self.entries[activity.id]?.generation == gen else { return }
            self.dismiss(id: activity.id)
        }
    }

    public func dismiss(id: String) {
        guard entries[id] != nil else { return }
        _ = withAnimation(.notchSpring) { entries.removeValue(forKey: id) }
    }

    public func dismiss(category: ActivityCategory) {
        let ids = entries.values.filter { $0.activity.category == category }.map(\.activity.id)
        withAnimation(.notchSpring) { ids.forEach { entries.removeValue(forKey: $0) } }
    }

    public func isPresented(id: String) -> Bool { entries[id] != nil }

    /// Swipe-to-dismiss: drops the top transient activity, or hides idle ones until something changes.
    public func dismissCurrent() {
        if let top = transientActivities.first {
            dismiss(id: top.id)
        }
    }

    public func cycleIdle(by delta: Int) {
        withAnimation(.notchSpring) { idleOffset += delta }
    }
}

public extension Animation {
    static let notchSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let notchSnappy = Animation.spring(response: 0.3, dampingFraction: 0.86)
}
