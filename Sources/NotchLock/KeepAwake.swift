import Foundation
import IOKit.pwr_mgt
import Observation

/// Holds a display-sleep assertion so lock screen widgets stay visible while music plays.
@MainActor
final class KeepAwake {
    private var assertionID: IOPMAssertionID?

    var isHeld: Bool { assertionID != nil }

    func set(_ hold: Bool) {
        hold ? acquire() : release()
    }

    private func acquire() {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Notch keeps the lock screen awake while media plays" as CFString,
            &id
        )
        if result == kIOReturnSuccess { assertionID = id }
    }

    private func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}

/// Re-runs `body` whenever any observable state it read changes, until cancelled.
@MainActor
final class ObservationLoop {
    private var isActive = true
    private let body: @MainActor () -> Void

    init(_ body: @escaping @MainActor () -> Void) {
        self.body = body
        track()
    }

    func cancel() { isActive = false }

    private func track() {
        guard isActive else { return }
        withObservationTracking(body) { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }
}
