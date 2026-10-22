import SwiftUI
import Observation
import NotchCore

@MainActor
@Observable
final class LockGlyphState {
    var isUnlocked = false
}

/// The closed-notch padlock shown while locked, which pops open on unlock before dismissing itself.
@MainActor
final class LockActivityController {
    static let activityID = "lock"
    private static let unlockLinger: TimeInterval = 0.475

    private let state = LockGlyphState()

    func showLocked() {
        if Defaults[LockSettings.playSoundOnLock] { SystemSound.lock.play() }
        guard Defaults[LockSettings.showLockActivity] else { return }
        state.isUnlocked = false
        ActivityCenter.shared.present(activity(duration: nil))
    }

    func showUnlocked() {
        if Defaults[LockSettings.playSoundOnUnlock] { SystemSound.unlock.play() }
        guard Defaults[LockSettings.showLockActivity] else {
            ActivityCenter.shared.dismiss(id: Self.activityID)
            return
        }
        let wasShowing = ActivityCenter.shared.isPresented(id: Self.activityID)
        if !wasShowing { state.isUnlocked = false }
        ActivityCenter.shared.present(activity(duration: Self.unlockLinger + (wasShowing ? 0 : 0.3)))
        // Flip after the activity is on screen so the replace transition and bounce are visible.
        Task { @MainActor [state] in
            try? await Task.sleep(for: .milliseconds(wasShowing ? 60 : 300))
            withAnimation(.notchSpring) { state.isUnlocked = true }
        }
    }

    func dismiss() {
        ActivityCenter.shared.dismiss(id: Self.activityID)
    }

    private func activity(duration: TimeInterval?) -> LiveActivity {
        LiveActivity(
            id: Self.activityID,
            category: .lock,
            priority: .critical,
            duration: duration,
            leadingWidth: 24,
            trailingWidth: 24
        ) {
            LockGlyph(state: state)
        } trailing: {
            Color.clear
        }
    }
}

private struct LockGlyph: View {
    let state: LockGlyphState

    var body: some View {
        Image(systemName: state.isUnlocked ? "lock.open.fill" : "lock.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: state.isUnlocked)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 1)
    }
}
