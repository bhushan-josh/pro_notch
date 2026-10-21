import NotchCore
import SwiftUI

public enum FileTrayStorageMode: String, CaseIterable, Sendable {
    case copy, reference

    public var title: String {
        switch self {
        case .copy: "Copy Files"
        case .reference: "Keep References"
        }
    }

    public var info: String {
        switch self {
        case .copy: "Dropped files are copied into the tray, so the originals can be moved or deleted."
        case .reference: "The tray points at the original files. Items disappear when their file is moved or deleted."
        }
    }
}

public enum FileTraySettings {
    public static let enabled = SettingKey("fileTray.enabled", default: true)
    public static let storage = SettingKey("fileTray.storage", default: FileTrayStorageMode.copy)
    public static let persist = SettingKey("fileTray.persist", default: true)
    public static let maxItems = SettingKey("fileTray.maxItems", default: 30)
    public static let showAirDropTarget = SettingKey("fileTray.showAirDropTarget", default: true)
    public static let showIdleIndicator = SettingKey("fileTray.showIdleIndicator", default: false)
}

struct FileTraySettingsView: View {
    let store: FileTrayStore

    @AppStorage(FileTraySettings.enabled) private var enabled
    @AppStorage(FileTraySettings.storage) private var storage
    @AppStorage(FileTraySettings.persist) private var persist
    @AppStorage(FileTraySettings.maxItems) private var maxItems
    @AppStorage(FileTraySettings.showAirDropTarget) private var showAirDropTarget
    @AppStorage(FileTraySettings.showIdleIndicator) private var showIdleIndicator

    var body: some View {
        SettingsPaneView {
            Section {
                SettingsToggle("Enable File Tray", info: "Drag files onto the notch to park them, then drag them out anywhere.", isOn: $enabled)
            }

            if enabled {
                Section("Storage") {
                    Picker("Dropped Files", selection: $storage) {
                        ForEach(FileTrayStorageMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text(storage.info).font(.caption).foregroundStyle(.secondary)
                    SettingsToggle("Keep Tray Between Launches", info: "Restore the tray contents when Notch starts.", isOn: $persist)
                    SettingsSlider(
                        "Maximum Items",
                        value: Binding(get: { Double(maxItems) }, set: { maxItems = Int($0.rounded()) }),
                        in: 5...100,
                        step: 5,
                        format: { String(format: "%.0f", $0) }
                    )
                }

                Section("Appearance") {
                    SettingsToggle("AirDrop Drop Target", info: "Show a target in the tray that sends dropped files with AirDrop.", isOn: $showAirDropTarget)
                    SettingsToggle("Idle Indicator", info: "Show the item count around the closed notch while the tray has files.", isOn: $showIdleIndicator)
                }

                Section {
                    LabeledContent("\(store.items.count) \(store.items.count == 1 ? "item" : "items") in tray") {
                        HStack {
                            Button("Reveal Tray Folder") { store.revealFolder() }
                            Button("Clear Tray", role: .destructive) { store.removeAll() }
                                .disabled(store.items.isEmpty)
                        }
                    }
                }
            }
        }
    }
}
