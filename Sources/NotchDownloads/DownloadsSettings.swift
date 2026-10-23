import Foundation
import NotchCore

public enum DownloadsSettings {
    public static let enabled = SettingKey("downloads.enabled", default: true)
    /// Extra folders to watch besides ~/Downloads, as absolute paths.
    public static let extraFolders = SettingKey("downloads.extraFolders", default: [String]())
    public static let showInNotch = SettingKey("downloads.showInNotch", default: true)
    public static let showPeek = SettingKey("downloads.showPeek", default: true)
    public static let notifyOnComplete = SettingKey("downloads.notifyOnComplete", default: true)
    public static let playSoundOnComplete = SettingKey("downloads.playSoundOnComplete", default: true)
    /// Downloads smaller than this many megabytes finish without a notch activity.
    public static let minimumSizeMB = SettingKey("downloads.minimumSizeMB", default: 0.0)
    /// Seconds a finished download stays on the Downloads page; the page disappears once the list is empty.
    public static let hideFinishedAfter = SettingKey("downloads.hideFinishedAfter", default: 30.0)

    static var folders: [URL] {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        let extra = Defaults[extraFolders].map { URL(fileURLWithPath: $0, isDirectory: true) }
        var seen = Set<String>()
        return (downloads + extra).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
