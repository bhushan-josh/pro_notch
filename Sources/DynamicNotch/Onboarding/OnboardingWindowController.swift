import AppKit
import NotchCore
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func show() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() })
        window.center()
        self.window = window
        // The close button must end onboarding too, or the Dock icon and the permission timer stay alive.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard let window else { return }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        self.window = nil
        window.contentView = nil
        window.close()
        NSApp.setActivationPolicy(.accessory)
        onFinish()
    }
}

private struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            if step == 0 {
                IntroStep { withAnimation(.notchSpring) { step = 1 } }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                PermissionsStep(onFinish: onFinish)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 520, height: 560)
        .background(.background)
    }
}

private struct IntroStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            NotchShape(topRadius: 10, bottomRadius: 22)
                .fill(.black)
                .frame(width: 260, height: 64)
                .overlay {
                    HStack {
                        RoundedRectangle(cornerRadius: 6).fill(.pink.gradient).frame(width: 30, height: 30)
                        Spacer()
                        Image(systemName: "waveform").foregroundStyle(.pink)
                    }
                    .padding(.horizontal, 26)
                }
            Text("Welcome to Dynamic Notch").font(.largeTitle.bold())
            Text("Live activities, media controls, HUDs and more, right where your camera sits.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            VStack(alignment: .leading, spacing: 14) {
                GestureRow(symbol: "cursorarrow.rays", title: "Hover or click", detail: "Open the expanded view.")
                GestureRow(symbol: "hand.draw", title: "Swipe down or up", detail: "Open or close with two fingers.")
                GestureRow(symbol: "arrow.left.arrow.right", title: "Swipe sideways", detail: "Skip to the next or previous track.")
            }
            .padding(.top, 8)
            Spacer()
            Button(action: onContinue) {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }
}

private struct GestureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionsStep: View {
    let onFinish: () -> Void
    @State private var refresh = 0
    private let registry = NotchRegistry.shared

    var body: some View {
        VStack(spacing: 18) {
            Text("Permissions").font(.largeTitle.bold()).padding(.top, 44)
            Text("Each feature only works once macOS allows it. You can change these later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(registry.permissions) { permission in
                        PermissionRow(permission: permission, refresh: $refresh)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 28)
            }
            Button(action: onFinish) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 60)
            .padding(.bottom, 32)
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in refresh += 1 }
    }
}
