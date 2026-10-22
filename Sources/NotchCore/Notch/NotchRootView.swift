import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    @Environment(NotchModel.self) private var model
    @AppStorage(CoreSettings.contrastOutline) private var contrastOutline
    private let center = ActivityCenter.shared
    private let registry = NotchRegistry.shared

    var body: some View {
        let activity = model.isOpen ? nil : center.current
        let open = model.isOpen
        let body = open
            ? NotchLayout.openSize(geometry: model.geometry)
            : NotchLayout.closedSize(geometry: model.geometry, activity: activity)
        let top = NotchLayout.topRadius(open: open)
        let bottom = NotchLayout.bottomRadius(open: open, geometry: model.geometry, activity: activity)
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(.black)
                    .shadow(color: .black.opacity(open ? 0.45 : 0), radius: open ? 16 : 0, y: 6)
                if contrastOutline {
                    shape.stroke(.white.opacity(0.14), lineWidth: 1)
                }
                content(activity: activity)
                    .padding(.horizontal, top)
                    .clipShape(shape)
            }
            .frame(width: body.width + top * 2, height: body.height)
            .contentShape(shape)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.shapeFrame = $0 }
            .onTapGesture { handleTap(activity: activity) }
            .onDrop(of: [.fileURL, .url, .image, .data], isTargeted: nil) { providers in
                registry.dropHandler?(providers) ?? false
            }
            .contextMenu { contextMenu }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(model.isSuppressed ? 0 : 1)
        .animation(.notchSpring, value: open)
        .animation(.notchSpring, value: activity?.id)
        .animation(.notchSpring, value: model.geometry)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(activity: LiveActivity?) -> some View {
        if model.isOpen {
            ExpandedNotchView()
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.notchSpring.delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let activity {
            ClosedActivityView(activity: activity, notchSize: model.geometry.notchSize)
                .id(activity.id)
                .transition(.opacity.combined(with: .blurReplace))
        }
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

struct ClosedActivityView: View {
    let activity: LiveActivity
    let notchSize: CGSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                activity.leading
                    .frame(width: activity.leadingWidth, height: notchSize.height)
                    .padding(.leading, NotchLayout.wingPadding)
                Spacer(minLength: notchSize.width + NotchLayout.wingPadding * 2)
                activity.trailing
                    .frame(width: activity.trailingWidth, height: notchSize.height)
                    .padding(.trailing, NotchLayout.wingPadding)
            }
            .frame(height: notchSize.height)
            if let bottom = activity.bottom {
                bottom
                    .frame(height: activity.bottomHeight)
                    .padding(.horizontal, NotchLayout.wingPadding + 4)
            }
        }
        .foregroundStyle(.white)
    }
}

struct ExpandedNotchView: View {
    @Environment(NotchModel.self) private var model
    private let registry = NotchRegistry.shared

    var body: some View {
        let pages = registry.pages
        let selected = pages.first { $0.id == model.selectedPageID } ?? pages.first
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    if pages.count > 1 {
                        ForEach(pages) { page in
                            PageTabButton(page: page, isSelected: page.id == selected?.id) {
                                withAnimation(.notchSnappy) { model.selectedPageID = page.id }
                            }
                        }
                    }
                }
                Spacer(minLength: model.geometry.notchSize.width + 16)
                Button {
                    registry.openSettings?(nil)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
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
        .foregroundStyle(.white)
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
                .frame(width: 30, height: 24)
                .background(isSelected ? .white.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(page.title)
    }
}

struct HomePageView: View {
    @AppStorage(CoreSettings.expandedHome) private var home
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
