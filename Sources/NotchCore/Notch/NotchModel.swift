import AppKit
import SwiftUI
import Observation

public struct NotchGeometry: Equatable, Sendable {
    /// Size of the camera housing (physical or simulated).
    public var notchSize: CGSize
    public var hasPhysicalNotch: Bool
    /// Draw a fake notch even when idle on a display without one.
    public var showsSimulatedNotch: Bool
    public var screenFrame: CGRect
    public var displayUUID: String

    @MainActor
    public static func make(for screen: NSScreen) -> NotchGeometry {
        let widthOffset = Defaults[CoreSettings.notchWidthOffset]
        let heightOffset = Defaults[CoreSettings.notchHeightOffset]
        let hasNotch = screen.hasPhysicalNotch
        var size: CGSize
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            size = CGSize(width: screen.frame.width - left - right, height: screen.safeAreaInsets.top)
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            size = CGSize(width: 185, height: max(menuBar > 0 ? menuBar : 24, 24))
        }
        size.width = max(80, size.width + widthOffset)
        size.height = max(18, size.height + heightOffset)
        return NotchGeometry(
            notchSize: size,
            hasPhysicalNotch: hasNotch,
            showsSimulatedNotch: !hasNotch && Defaults[CoreSettings.forceSimulatedNotch],
            screenFrame: screen.frame,
            displayUUID: screen.displayUUID
        )
    }
}

public enum NotchLayout {
    public static let expandedWidth: CGFloat = 576
    public static let expandedContentHeight: CGFloat = 158
    /// Inset between the island edge and wing content.
    public static let wingPadding: CGFloat = 9
    /// Gap kept clear on each side of the camera.
    public static let cameraGap: CGFloat = 4
    public static let horizontalContentPadding: CGFloat = 18
    public static let hoverScale: CGFloat = 1.075
    public static let pressScale: CGFloat = 0.94

    public static func topRadius(open: Bool) -> CGFloat { open ? 12 : 6 }

    public static func bottomRadius(open: Bool, hovering: Bool, activity: LiveActivity?) -> CGFloat {
        if open { return 24 }
        if let activity, activity.bottomHeight > 0 { return 19 }
        return hovering ? 13 : 12
    }

    /// Wings are always symmetric so the camera stays centered between them.
    public static func wingWidth(_ activity: LiveActivity) -> CGFloat {
        max(activity.leadingWidth, activity.trailingWidth)
    }

    /// Body size excluding the top flares the shape adds on each side.
    public static func closedSize(geometry: NotchGeometry, activity: LiveActivity?) -> CGSize {
        let notch = geometry.notchSize
        guard let activity else {
            let visible = geometry.hasPhysicalNotch || geometry.showsSimulatedNotch
            return visible ? notch : CGSize(width: notch.width * 0.6, height: 0)
        }
        return CGSize(
            width: notch.width + (wingWidth(activity) + wingPadding + cameraGap) * 2,
            height: notch.height + activity.bottomHeight
        )
    }

    public static func openSize(geometry: NotchGeometry) -> CGSize {
        CGSize(
            width: max(expandedWidth, geometry.notchSize.width + 340),
            height: geometry.notchSize.height + expandedContentHeight
        )
    }

    /// Window size large enough for every state, the hover scale and the shadow.
    public static func windowSize(geometry: NotchGeometry) -> CGSize {
        let open = openSize(geometry: geometry)
        return CGSize(width: open.width + topRadius(open: true) * 2 + 120, height: open.height + 60)
    }
}

/// Per-screen notch state. Feature views can read it with `@Environment(NotchModel.self)`.
@MainActor
@Observable
public final class NotchModel {
    public internal(set) var geometry: NotchGeometry
    public internal(set) var isOpen = false
    public internal(set) var isHovering = false
    /// Mouse button held on the closed island.
    public internal(set) var isPressed = false
    public var selectedPageID = NotchModel.homePageID
    /// Files are being dragged over the notch.
    public internal(set) var isDropTargeted = false
    /// The display is showing a fullscreen app and the user asked to hide the notch there.
    public internal(set) var isHiddenForFullscreen = false
    /// Frame of the visible shape in window coordinates (top-left origin).
    public internal(set) var shapeFrame: CGRect = .zero

    public static let homePageID = "home"

    @ObservationIgnored var onOpenChange: ((Bool) -> Void)?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    public func open(page: String? = nil) {
        if let page { selectedPageID = page }
        guard !isOpen else { return }
        isOpen = true
        isPressed = false
        Haptics.perform()
        onOpenChange?(true)
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        onOpenChange?(false)
    }

    public func toggle() { isOpen ? close() : open() }

    /// Hidden for fullscreen unless something transient (a volume change, a charger) needs showing.
    public var isSuppressed: Bool {
        isHiddenForFullscreen && ActivityCenter.shared.transientActivities.isEmpty
    }
}
