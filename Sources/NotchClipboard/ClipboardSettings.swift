import Foundation
import NotchCore

public enum ClipboardSettings {
    public static let enabled = SettingKey("clipboard.enabled", default: true)
    /// Unpinned items kept in history; pinned items never count against it.
    public static let maxItems = SettingKey("clipboard.maxItems", default: 30)
    public static let persist = SettingKey("clipboard.persist", default: true)
    public static let showCopiedActivity = SettingKey("clipboard.showCopiedActivity", default: false)
    /// Bundle IDs whose copies are never recorded while they are frontmost.
    public static let ignoredApps = SettingKey("clipboard.ignoredApps", default: defaultIgnoredApps)

    static let defaultIgnoredApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
    ]

    /// Names for the defaults so the list reads well even when an app is not installed.
    static let knownAppNames = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "org.keepassxc.keepassxc": "KeePassXC",
        "com.apple.Passwords": "Passwords",
        "com.apple.keychainaccess": "Keychain Access",
    ]

    static let maxItemChoices = [10, 20, 30, 50, 100]
}
