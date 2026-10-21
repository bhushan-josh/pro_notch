import NotchCore

public enum ConnectivityStyle: String, CaseIterable, Sendable {
    case symbol, threeDimensional

    public var title: String {
        switch self {
        case .symbol: "Symbol"
        case .threeDimensional: "3D"
        }
    }
}

public enum ConnectivitySettings {
    public static let enabled = SettingKey("connectivity.enabled", default: true)
    public static let showBattery = SettingKey("connectivity.showBattery", default: true)
    public static let playSound = SettingKey("connectivity.playSound", default: true)
    public static let style = SettingKey("connectivity.style", default: ConnectivityStyle.symbol)
}
