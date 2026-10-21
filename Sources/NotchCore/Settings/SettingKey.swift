import SwiftUI

/// A typed UserDefaults key. Read from code with `Defaults[key]`, bind in SwiftUI with `@AppStorage(key)`.
public struct SettingKey<Value>: Sendable where Value: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public enum Defaults {
    public static let store = UserDefaults.standard

    public static subscript(key: SettingKey<Bool>) -> Bool {
        get { store.object(forKey: key.name) as? Bool ?? key.defaultValue }
        set { store.set(newValue, forKey: key.name) }
    }

    public static subscript(key: SettingKey<Int>) -> Int {
        get { store.object(forKey: key.name) as? Int ?? key.defaultValue }
        set { store.set(newValue, forKey: key.name) }
    }

    public static subscript(key: SettingKey<Double>) -> Double {
        get { store.object(forKey: key.name) as? Double ?? key.defaultValue }
        set { store.set(newValue, forKey: key.name) }
    }

    public static subscript(key: SettingKey<String>) -> String {
        get { store.string(forKey: key.name) ?? key.defaultValue }
        set { store.set(newValue, forKey: key.name) }
    }

    public static subscript<E: RawRepresentable>(key: SettingKey<E>) -> E where E.RawValue == String {
        get { store.string(forKey: key.name).flatMap(E.init(rawValue:)) ?? key.defaultValue }
        set { store.set(newValue.rawValue, forKey: key.name) }
    }

    public static subscript(key: SettingKey<[String]>) -> [String] {
        get { store.stringArray(forKey: key.name) ?? key.defaultValue }
        set { store.set(newValue, forKey: key.name) }
    }

    /// Fires on the main queue whenever any of the given keys change, from any source (code or `@AppStorage`).
    @MainActor
    public static func observe(_ names: [String], _ handler: @escaping @MainActor () -> Void) -> AnyObject {
        let observer = DefaultsObserver(names: names, handler: handler)
        return observer
    }
}

/// KVO can't be used here: it reads dotted names like "general.displayTarget" as nested key paths.
@MainActor
private final class DefaultsObserver {
    private let names: [String]
    private let handler: @MainActor () -> Void
    private var snapshot: [String: NSObject?]
    private var token: NSObjectProtocol?

    init(names: [String], handler: @escaping @MainActor () -> Void) {
        self.names = names
        self.handler = handler
        snapshot = Self.read(names)
        token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    isolated deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    private func check() {
        let current = Self.read(names)
        guard current != snapshot else { return }
        snapshot = current
        handler()
    }

    private static func read(_ names: [String]) -> [String: NSObject?] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, Defaults.store.object(forKey: $0) as? NSObject) })
    }
}

public extension AppStorage where Value == Bool {
    init(_ key: SettingKey<Bool>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

public extension AppStorage where Value == Int {
    init(_ key: SettingKey<Int>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

public extension AppStorage where Value == Double {
    init(_ key: SettingKey<Double>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

public extension AppStorage where Value == String {
    init(_ key: SettingKey<String>) { self.init(wrappedValue: key.defaultValue, key.name) }
}

public extension AppStorage {
    init(_ key: SettingKey<Value>) where Value: RawRepresentable, Value.RawValue == String {
        self.init(wrappedValue: key.defaultValue, key.name)
    }
}
