import SwiftUI

struct NotchRootView: View {
    @Environment(NotchModel.self) private var model
    @AppStorage(CoreSettings.contrastOutline) private var contrastOutline
    @State private var previousKind = IslandKind.idle
    private let center = ActivityCenter.shared
    private let registry = NotchRegistry.shared

    var body: some View {
        let open = model.isOpen
        let activity = open ? nil : center.current
        let kind = IslandKind(open: open, activity: activity)
        let hovering = model.isHovering && !open
        let page = registry.pages.first { $0.id == model.selectedPageID } ?? registry.pages.first
        let size = open
            ? NotchLayout.openSize(geometry: model.geometry, page: page)
            : NotchLayout.closedSize(geometry: model.geometry, activity: activity)
        let top = NotchLayout.topRadius(open: open)
        let bottom = NotchLayout.bottomRadius(open: open, hovering: hovering, activity: activity)
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)
        let scale = open ? 1 : (model.isPressed ? NotchLayout.pressScale : (hovering ? NotchLayout.hoverScale : 1))

        VStack(spacing: 0) {
            if !model.isSuppressed {
                // The clip sits on the animated frame, not on the content: inserted content is laid out at its
                // final size at once, so only a frame-level clip reveals it in step with the growing panel.
                ZStack(alignment: .top) {
                    if open {
                        ExpandedNotchView().transition(.islandExpanded)
                    } else {
                        ClosedActivityView(activity: activity, notchSize: model.geometry.notchSize)
                    }
                }
                .padding(.horizontal, top)
                .frame(width: size.width + top * 2, height: size.height, alignment: .top)
                .clipShape(shape)
                .background {
                    shape
                        .fill(.black)
                        .shadow(color: .black.opacity(open ? 0.4 : (hovering ? 0.25 : 0)), radius: open ? 18 : 8, y: open ? 8 : 2)
                }
                .overlay {
                    if contrastOutline { shape.stroke(.white.opacity(0.14), lineWidth: 1) }
                }
                .scaleEffect(scale, anchor: .top)
                .contentShape(shape)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.shapeFrame = $0 }
                .onTapGesture { handleTap(activity: activity) }
                .contextMenu { contextMenu }
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: model.isSuppressed)
        .animation(IslandKind.animation(from: previousKind, to: kind), value: kind)
        .animation(IslandKind.animation(from: previousKind, to: kind), value: activity?.id)
        .animation(hovering ? .islandHover : .islandUnhover, value: hovering)
        .animation(.islandPress, value: model.isPressed)
        .animation(.islandExpand, value: model.selectedPageID)
        .animation(.islandExpand, value: model.geometry)
        .onChange(of: kind) { _, new in previousKind = new }
        .ignoresSafeArea()
    }

    private func handleTap(activity: LiveActivity?) {
        guard !model.isOpen else { return }
        if let onTap = activity?.onTap {
            onTap()
        } else {
            model.open()
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Settings…") { registry.openSettings?(nil) }
        Divider()
        Button("Quit Dynamic Notch") { NSApp.terminate(nil) }
    }
}

/// Which shape the island is in; each change between kinds uses its own spring.
enum IslandKind: Equatable {
    case idle, wings, peek, open

    init(open: Bool, activity: LiveActivity?) {
        if open { self = .open } else if let activity { self = activity.bottom == nil ? .wings : .peek } else { self = .idle }
    }

    static func animation(from old: IslandKind, to new: IslandKind) -> Animation {
        switch (old, new) {
        case (_, .open): .islandOpen
        case (.open, _): .islandClose
        case (_, .peek): .islandPeekOpen
        case (.peek, _): .islandPeekClose
        case (_, .idle): .islandCollapse
        default: .islandExpand
        }
    }
}

struct ClosedActivityView: View {
    let activity: LiveActivity?
    let notchSize: CGSize

    var body: some View {
        let wing = activity.map(NotchLayout.wingWidth) ?? 0
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    if let activity {
                        activity.leading.id(activity.id).transition(.islandWing)
                    }
                }
                .frame(width: wing, height: notchSize.height)
                .padding(.leading, NotchLayout.wingPadding)
                Spacer(minLength: notchSize.width + NotchLayout.cameraGap * 2)
                ZStack {
                    if let activity {
                        activity.trailing.id(activity.id).transition(.islandWing)
                    }
                }
                .frame(width: wing, height: notchSize.height)
                .padding(.trailing, NotchLayout.wingPadding)
            }
            .frame(height: notchSize.height)
            ZStack {
                if let activity, let bottom = activity.bottom {
                    bottom
                        .id(activity.id)
                        .frame(height: activity.bottomHeight)
                        .padding(.horizontal, NotchLayout.wingPadding + 4)
                        .transition(.islandPeek)
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct ExpandedNotchView: View {
    @Environment(NotchModel.self) private var model
    private let registry = NotchRegistry.shared

    private static let tabWidth: CGFloat = 26
    private static let tabSpacing: CGFloat = 2

    var body: some View {
        let pages = registry.pages
        let selected = pages.first { $0.id == model.selectedPageID } ?? pages.first
        let layout = tabLayout(pages: pages, selected: selected)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: Self.tabSpacing) {
                    ForEach(layout.left) { tab($0, selected: selected) }
                }
                Spacer(minLength: model.geometry.notchSize.width + 16)
                HStack(spacing: Self.tabSpacing) {
                    ForEach(layout.right) { tab($0, selected: selected) }
                    if !layout.overflow.isEmpty { overflowMenu(layout.overflow, selected: selected) }
                    ForEach(registry.headerAccessories) { $0.content().frame(width: Self.tabWidth, height: 24) }
                    Button {
                        registry.openSettings?(nil)
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: Self.tabWidth, height: 26)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: model.geometry.notchSize.height)
            .padding(.horizontal, NotchLayout.horizontalContentPadding - 6)

            Group {
                if let selected {
                    selected.content()
                        .id(selected.id)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, NotchLayout.horizontalContentPadding)
            .padding(.bottom, 14)
            .padding(.top, 4)
        }
        .overlay {
            if let selected, let resize = selected.resize {
                PageResizeHandles(page: selected, resize: resize)
            }
        }
        .foregroundStyle(.white)
    }

    private func tab(_ page: NotchPage, selected: NotchPage?) -> some View {
        PageTabButton(page: page, isSelected: page.id == selected?.id) {
            withAnimation(.notchSnappy) { model.selectedPageID = page.id }
        }
    }

    private func overflowMenu(_ pages: [NotchPage], selected: NotchPage?) -> some View {
        let isSelected = pages.contains { $0.id == selected?.id }
        return Menu {
            ForEach(pages) { page in
                Button { withAnimation(.notchSnappy) { model.selectedPageID = page.id } } label: {
                    Label(page.title, systemImage: page.symbol)
                }
            }
        } label: {
            Image(systemName: isSelected ? (selected?.symbol ?? "ellipsis") : "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .frame(width: Self.tabWidth, height: 24)
                .background(isSelected ? .white.opacity(0.14) : .clear, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Tabs fill the space left of the camera first, then right of it before the header buttons;
    /// whatever still does not fit goes into a "More" menu.
    private func tabLayout(pages: [NotchPage], selected: NotchPage?) -> (left: [NotchPage], right: [NotchPage], overflow: [NotchPage]) {
        guard pages.count > 1 else { return ([], [], []) }
        let open = NotchLayout.openSize(geometry: model.geometry, page: selected)
        let side = (open.width - model.geometry.notchSize.width - 16) / 2 - (NotchLayout.horizontalContentPadding - 6)
        let slot = Self.tabWidth + Self.tabSpacing
        let leftCapacity = max(1, Int(side / slot))
        let reserved = CGFloat(registry.headerAccessories.count + 1) * slot
        let rightCapacity = max(0, Int((side - reserved) / slot))
        if pages.count <= leftCapacity + rightCapacity {
            let left = Array(pages.prefix(leftCapacity))
            return (left, Array(pages.dropFirst(left.count)), [])
        }
        let left = Array(pages.prefix(leftCapacity))
        let rest = Array(pages.dropFirst(leftCapacity))
        let rightCount = max(0, rightCapacity - 1)
        return (left, Array(rest.prefix(rightCount)), Array(rest.dropFirst(rightCount)))
    }
}

private struct PageTabButton: View {
    let page: NotchPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: page.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
                .frame(width: 26, height: 24)
                .background(isSelected ? .white.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(page.title)
    }
}

struct HomePageView: View {
    @AppStorage(CoreSettings.expandedHome) private var home
    @State private var narrowIndex = 0
    private let registry = NotchRegistry.shared

    var body: some View {
        let kinds: [HomeWidgetKind] = switch home {
        case .duo: [.nowPlaying, .calendar]
        case .nowPlaying: [.nowPlaying]
        case .calendar: [.calendar]
        case .none: []
        }
        let widgets = kinds.compactMap { kind in registry.homeWidgets.first { $0.kind == kind } }
        if widgets.isEmpty {
            EmptyHomeView()
        } else {
            GeometryReader { proxy in
                if widgets.count > 1, proxy.size.width < NotchLayout.duoMinimumWidth {
                    single(widgets)
                } else {
                    sideBySide(widgets)
                }
            }
        }
    }

    private func sideBySide(_ widgets: [HomeWidget]) -> some View {
        HStack(spacing: 18) {
            ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.1)).frame(width: 1).padding(.vertical, 8)
                }
                widget.content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Too narrow for Duo: one card at a time, with dots to switch.
    private func single(_ widgets: [HomeWidget]) -> some View {
        let index = min(narrowIndex, widgets.count - 1)
        return widgets[index].content()
            .id(widgets[index].id)
            .transition(.opacity.combined(with: .blurReplace))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 5) {
                    ForEach(widgets.indices, id: \.self) { dot in
                        Circle()
                            .fill(.white.opacity(dot == index ? 0.8 : 0.25))
                            .frame(width: 5, height: 5)
                            .padding(3)
                            .contentShape(Circle())
                            .onTapGesture { withAnimation(.notchSnappy) { narrowIndex = dot } }
                    }
                }
                .offset(y: -14)
            }
    }
}

private struct EmptyHomeView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 4) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text(context.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
