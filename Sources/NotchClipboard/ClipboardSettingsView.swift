import AppKit
import NotchCore
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    let store: ClipboardStore
    @AppStorage(ClipboardSettings.enabled) private var enabled
    @AppStorage(ClipboardSettings.maxItems) private var maxItems
    @AppStorage(ClipboardSettings.persist) private var persist
    @AppStorage(ClipboardSettings.showCopiedActivity) private var showCopied
    @State private var ignoredApps = Defaults[ClipboardSettings.ignoredApps]
    @State private var confirmClear = false

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Clipboard History", info: "Keeps recent text, links, files and images you copy on the Clipboard page.", isOn: $enabled)
            }
            if enabled {
                Section {
                    Picker("Keep Recent Items", selection: $maxItems) {
                        ForEach(choices, id: \.self) { Text("\($0)").tag($0) }
                    }
                    SettingsToggle("Remember After Quitting", info: "Saves history on this Mac only, in Application Support.", isOn: $persist)
                    SettingsToggle("Pulse the Notch When You Copy", info: "Briefly shows a checkmark around the closed notch.", isOn: $showCopied)
                } header: {
                    Text("History")
                } footer: {
                    Text("Pinned items stay on top and do not count against the limit.")
                }
                Section {
                    ForEach(ignoredApps, id: \.self) { bundleID in
                        IgnoredAppRow(bundleID: bundleID) {
                            setIgnoredApps(ignoredApps.filter { $0 != bundleID })
                        }
                    }
                    Button("Add App…") { chooseApp() }
                } header: {
                    Text("Ignored Apps")
                } footer: {
                    Text("Nothing is recorded while these apps are in front. Items that password managers mark as concealed or transient are always skipped.")
                }
                Section {
                    LabeledContent("\(store.items.count) items in history") {
                        Button("Clear History…") { confirmClear = true }
                            .disabled(store.items.isEmpty)
                    }
                }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear All, Including Pinned", role: .destructive) { store.clear(keepingPinned: false) }
            Button("Clear All but Pinned") { store.clear(keepingPinned: true) }
        } message: {
            Text("Saved items are deleted from disk as well.")
        }
    }

    private var choices: [Int] {
        ClipboardSettings.maxItemChoices.contains(maxItems)
            ? ClipboardSettings.maxItemChoices
            : (ClipboardSettings.maxItemChoices + [maxItems]).sorted()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        setIgnoredApps(ignoredApps + added)
    }

    private func setIgnoredApps(_ apps: [String]) {
        var seen = Set<String>()
        ignoredApps = apps.filter { seen.insert($0).inserted }
        Defaults[ClipboardSettings.ignoredApps] = ignoredApps
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        LabeledContent {
            Button("Remove", action: onRemove)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let appURL {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                Text(name(appURL))
            }
        }
        .help(bundleID)
    }

    private func name(_ appURL: URL?) -> String {
        if let appURL {
            return (FileManager.default.displayName(atPath: appURL.path) as NSString).deletingPathExtension
        }
        return ClipboardSettings.knownAppNames[bundleID] ?? bundleID
    }
}
