import SwiftUI

/// Spring constants measured from Alcove's own web replica of the island (tryalcove.com).
public extension Animation {
    static let islandHover = Animation.interpolatingSpring(mass: 1, stiffness: 250, damping: 14)
    static let islandUnhover = Animation.interpolatingSpring(mass: 1, stiffness: 200, damping: 20)
    static let islandPress = Animation.interpolatingSpring(mass: 1, stiffness: 160, damping: 18)
    static let islandExpand = Animation.interpolatingSpring(mass: 1, stiffness: 150, damping: 20)
    static let islandCollapse = Animation.interpolatingSpring(mass: 1, stiffness: 175, damping: 17.5)
    static let islandPeekOpen = Animation.interpolatingSpring(mass: 1, stiffness: 250, damping: 21)
    static let islandPeekClose = Animation.interpolatingSpring(mass: 1, stiffness: 250, damping: 25)
    static let islandOpen = Animation.interpolatingSpring(mass: 1, stiffness: 230, damping: 22)
    static let islandClose = Animation.interpolatingSpring(mass: 1, stiffness: 250, damping: 26)
}

public struct IslandBlurEffect: ViewModifier {
    var opacity: Double
    var blur: CGFloat
    var scaleX: CGFloat
    var scaleY: CGFloat = 1
    var anchor: UnitPoint = .center

    public func body(content: Content) -> some View {
        content
            .scaleEffect(x: scaleX, y: scaleY, anchor: anchor)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

public extension AnyTransition {
    /// Wing content: grows out of the camera sideways from a blur, shrinks back into one.
    static var islandWing: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 10, scaleX: 0.01),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1)
            ).animation(.easeInOut(duration: 0.3)),
            removal: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 4, scaleX: 0.25),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1)
            ).animation(.easeInOut(duration: 0.25))
        )
    }

    /// The strip under the camera during a quick peek.
    static var islandPeek: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 10, scaleX: 0.75, anchor: .top),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1, anchor: .top)
            ).animation(.islandPeekOpen.delay(0.05)),
            removal: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 10, scaleX: 0.75, anchor: .top),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1, anchor: .top)
            ).animation(.islandPeekClose)
        )
    }

    /// Expanded content settling in from a blur once the island has mostly opened, so the text never runs ahead of the shape.
    static var islandExpanded: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 10, scaleX: 0.96, scaleY: 0.94, anchor: .top),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1, anchor: .top)
            ).animation(.easeOut(duration: 0.26).delay(0.17)),
            removal: .modifier(
                active: IslandBlurEffect(opacity: 0, blur: 8, scaleX: 0.92, scaleY: 0.85, anchor: .top),
                identity: IslandBlurEffect(opacity: 1, blur: 0, scaleX: 1, anchor: .top)
            ).animation(.easeIn(duration: 0.16))
        )
    }
}
