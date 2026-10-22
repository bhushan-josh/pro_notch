import SwiftUI

/// Bottom-edge grabber and bottom corners for a resizable page. The island stays centered under the camera,
/// so a corner drag changes the width by twice the horizontal movement.
struct PageResizeHandles: View {
    let page: NotchPage
    let resize: PageResize

    @Environment(NotchModel.self) private var model
    @State private var startSize: CGSize?
    @State private var isHoveringGrabber = false

    private let store = PageSizeStore.shared

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                corner(side: -1)
                Spacer()
                grabber
                Spacer()
                corner(side: 1)
            }
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(isHoveringGrabber || startSize != nil ? 0.45 : 0.16))
            .frame(width: 38, height: 4)
            .padding(.vertical, 5)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(.easeOut(duration: 0.15)) { isHoveringGrabber = hovering } }
            .pointerStyle(.frameResize(position: .bottom))
            .gesture(drag(horizontal: 0))
            .onTapGesture(count: 2) { resetSize() }
            .help("Drag to resize. Double-click to reset.")
    }

    private func corner(side: CGFloat) -> some View {
        Color.clear
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: side < 0 ? .bottomLeading : .bottomTrailing))
            .gesture(drag(horizontal: side))
            .onTapGesture(count: 2) { resetSize() }
    }

    private func drag(horizontal side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let base = startSize ?? NotchLayout.openSize(geometry: model.geometry, page: page)
                if startSize == nil {
                    startSize = base
                    model.isResizing = true
                }
                let proposed = CGSize(
                    width: base.width + value.translation.width * 2 * side,
                    height: base.height + value.translation.height
                )
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { store.setLive(resize.clamp(proposed), for: page.id) }
            }
            .onEnded { _ in
                store.persist(page.id)
                startSize = nil
                model.isResizing = false
            }
    }

    private func resetSize() {
        withAnimation(.islandExpand) { store.reset(page.id) }
    }
}
