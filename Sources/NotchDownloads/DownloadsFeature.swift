import AppKit
import NotchCore
import SwiftUI

@MainActor
public final class DownloadsFeature: NotchFeature {
    public static let pageID = "downloads"
    static let progressActivityID = "downloads.progress"
    static let doneActivityID = "downloads.done"

    private let monitor = DownloadMonitor()
    private var settingsObserver: AnyObject?
    private var peekTask: Task<Void, Never>?

    public init() {}

    public func start() {
        let registry = NotchRegistry.shared
        registry.register(settingsPane: SettingsPane(id: "downloads", title: "Downloads", symbol: "arrow.down.circle.fill", color: .cyan, order: 75) {
            DownloadsSettingsView()
        })
        registry.register(permission: Self.permission)

        monitor.onStart = { [weak self] item in self?.started(item) }
        monitor.onUpdate = { [weak self] in self?.refreshProgressActivity(withPeek: nil) }
        monitor.onFinish = { [weak self] item in self?.finished(item) }
        monitor.onEmptyChange = { [weak self] isEmpty in self?.updatePage(visible: !isEmpty) }

        apply()
        settingsObserver = Defaults.observe([DownloadsSettings.enabled.name, DownloadsSettings.extraFolders.name]) { [weak self] in
            self?.apply()
        }
    }

    public func stop() {
        updatePage(visible: false)
        monitor.stop()
        peekTask?.cancel()
        ActivityCenter.shared.dismiss(id: Self.progressActivityID)
        settingsObserver = nil
    }

    private func apply() {
        let enabled = Defaults[DownloadsSettings.enabled]
        if enabled {
            monitor.start()
            updatePage(visible: !monitor.items.isEmpty)
        } else {
            updatePage(visible: false)
            monitor.stop()
            ActivityCenter.shared.dismiss(id: Self.progressActivityID)
        }
    }

    /// The Downloads tab exists only while the list has something in it.
    private func updatePage(visible: Bool) {
        let registry = NotchRegistry.shared
        if visible, Defaults[DownloadsSettings.enabled] {
            guard !registry.pages.contains(where: { $0.id == Self.pageID }) else { return }
            let monitor = monitor
            withAnimation(.notchSnappy) {
                registry.register(page: NotchPage(id: Self.pageID, title: "Downloads", symbol: "arrow.down.circle.fill", order: 20) {
                    DownloadsPage(monitor: monitor)
                })
            }
        } else {
            for model in NotchManager.shared.models where model.selectedPageID == Self.pageID {
                model.selectedPageID = NotchModel.homePageID
            }
            withAnimation(.notchSnappy) { registry.unregister(pageID: Self.pageID) }
        }
    }

    // MARK: Activities

    private func isLargeEnough(_ item: DownloadItem) -> Bool {
        let minimum = Defaults[DownloadsSettings.minimumSizeMB] * 1_000_000
        return item.totalBytes <= 0 || Double(item.totalBytes) >= minimum
    }

    private func started(_ item: DownloadItem) {
        guard isLargeEnough(item) else { return }
        let peek = Defaults[DownloadsSettings.showPeek]
        refreshProgressActivity(withPeek: peek)
        guard peek else { return }
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.refreshProgressActivity(withPeek: false)
        }
    }

    private var showsPeek = false

    /// Keeps one persistent activity while anything downloads; the same id updates in place.
    private func refreshProgressActivity(withPeek peek: Bool?) {
        if let peek { showsPeek = peek }
        let active = monitor.activeItems.filter(isLargeEnough)
        guard Defaults[DownloadsSettings.showInNotch], !active.isEmpty else {
            ActivityCenter.shared.dismiss(id: Self.progressActivityID)
            return
        }
        guard peek != nil || !ActivityCenter.shared.isPresented(id: Self.progressActivityID) else { return }
        let monitor = monitor
        var activity = LiveActivity(
            id: Self.progressActivityID,
            category: .other,
            priority: .normal,
            duration: nil,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { DownloadLeadingWing(monitor: monitor) },
            trailing: { DownloadTrailingWing(monitor: monitor) },
            onTap: { NotchManager.shared.activeModel?.open(page: DownloadsFeature.pageID) }
        )
        if showsPeek {
            activity = activity.withBottom(height: 32) { DownloadPeek(monitor: monitor) }
        }
        ActivityCenter.shared.present(activity)
    }

    private func finished(_ item: DownloadItem) {
        refreshProgressActivity(withPeek: nil)
        guard isLargeEnough(item), Defaults[DownloadsSettings.notifyOnComplete] else { return }
        if item.state == .finished, Defaults[DownloadsSettings.playSoundOnComplete] {
            SystemSound.pop.play()
        }
        let url = item.fileURL
        let finishedOK = item.state == .finished
        ActivityCenter.shared.present(LiveActivity(
            id: Self.doneActivityID,
            category: .other,
            priority: .high,
            duration: 3,
            leadingWidth: 22,
            trailingWidth: 22,
            leading: { DownloadDoneLeading(item: item) },
            trailing: { DownloadDoneTrailing(item: item) },
            onTap: {
                if finishedOK { NSWorkspace.shared.open(url) } else { NotchManager.shared.activeModel?.open(page: DownloadsFeature.pageID) }
            }
        ).withBottom(height: 32) { DownloadDonePeek(item: item) })
    }

    // MARK: Permission

    static let permission = PermissionRequirement(
        id: "downloads.folder",
        title: "Downloads Folder",
        description: "Lets Dynamic Notch show what is downloading and open finished files.",
        symbol: "arrow.down.circle",
        settingsURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"),
        status: { canReadDownloads ? .granted : .notDetermined },
        request: { _ = canReadDownloads }
    )

    /// Listing the folder is also what triggers the system's Downloads access prompt.
    private static var canReadDownloads: Bool {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }
}

struct DownloadsSettingsView: View {
    @AppStorage(DownloadsSettings.enabled) private var enabled
    @AppStorage(DownloadsSettings.showInNotch) private var showInNotch
    @AppStorage(DownloadsSettings.showPeek) private var showPeek
    @AppStorage(DownloadsSettings.notifyOnComplete) private var notifyOnComplete
    @AppStorage(DownloadsSettings.playSoundOnComplete) private var playSound
    @AppStorage(DownloadsSettings.minimumSizeMB) private var minimumSize
    @AppStorage(DownloadsSettings.hideFinishedAfter) private var hideAfter
    @State private var extraFolders = Defaults[DownloadsSettings.extraFolders]

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Track Downloads", info: "Shows progress for files downloading in Safari, Chrome, Brave, Firefox and other apps that report to Finder.", isOn: $enabled)
            }
            if enabled {
                Section("Notch") {
                    Toggle("Show Progress in Notch", isOn: $showInNotch)
                    SettingsToggle("Show File Name When a Download Starts", info: "A short peek with the name, size and time left.", isOn: $showPeek)
                    Toggle("Show When a Download Finishes", isOn: $notifyOnComplete)
                    Toggle("Play Sound When Finished", isOn: $playSound)
                    SettingsSlider("Ignore Downloads Smaller Than", value: $minimumSize, in: 0...100, step: 1, format: { $0 == 0 ? "Off" : "\(Int($0)) MB" })
                }
                Section("Downloads Page") {
                    SettingsSlider("Hide Finished Downloads After", value: $hideAfter, in: 5...300, step: 5, format: { "\(Int($0)) s" })
                }
                Section {
                    LabeledContent("Downloads") { Text("~/Downloads").foregroundStyle(.secondary) }
                    ForEach(extraFolders, id: \.self) { path in
                        LabeledContent((path as NSString).lastPathComponent) {
                            Button("Remove") { setFolders(extraFolders.filter { $0 != path }) }
                        }
                        .help(path)
                    }
                    Button("Add Folder…") { chooseFolder() }
                } header: {
                    Text("Watched Folders")
                } footer: {
                    Text("Add the folder your browser saves to if it is not Downloads.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolders(extraFolders + [url.path])
    }

    private func setFolders(_ folders: [String]) {
        var seen = Set<String>()
        extraFolders = folders.filter { seen.insert($0).inserted }
        Defaults[DownloadsSettings.extraFolders] = extraFolders
    }
}
