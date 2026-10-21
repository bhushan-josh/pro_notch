import AppKit
import NotchCore
import SwiftUI

enum FocusCatalog {
    static let sleepIdentifier = "com.apple.sleep.sleep-mode"

    private struct Known {
        let name: String
        let symbol: String
        let color: Color
    }

    private static let known: [String: Known] = [
        "com.apple.donotdisturb.mode.default": Known(name: "Do Not Disturb", symbol: "moon.fill", color: .indigo),
        sleepIdentifier: Known(name: "Sleep", symbol: "bed.double.fill", color: .mint),
        "com.apple.donotdisturb.mode.driving": Known(name: "Driving", symbol: "car.fill", color: .blue),
        "com.apple.donotdisturb.mode.workout": Known(name: "Fitness", symbol: "figure.run", color: .green),
        "com.apple.focus.work": Known(name: "Work", symbol: "briefcase.fill", color: .teal),
        "com.apple.focus.personal-time": Known(name: "Personal", symbol: "person.fill", color: .purple),
        "com.apple.focus.reading": Known(name: "Reading", symbol: "book.fill", color: .orange),
        "com.apple.focus.gaming": Known(name: "Gaming", symbol: "gamecontroller.fill", color: .blue),
        "com.apple.focus.mindfulness": Known(name: "Mindfulness", symbol: "brain.head.profile", color: .cyan),
        "com.apple.focus.reduce-interruptions": Known(name: "Reduce Interruptions", symbol: "apple.intelligence", color: .pink),
    ]

    @MainActor
    static func info(for identifier: String, config: FocusModeConfig?) -> FocusModeInfo {
        let builtIn = known[identifier]
        let name = nonEmpty(config?.name) ?? builtIn?.name ?? "Focus"
        let symbol = [builtIn?.symbol, config?.symbol, "moon.fill"]
            .compactMap { $0 }
            .first(where: symbolExists) ?? "moon.fill"
        let color = builtIn?.color ?? color(named: config?.tint) ?? .indigo
        return FocusModeInfo(identifier: identifier, name: name, symbol: symbol, color: color)
    }

    /// Focus configs store UIKit-style names such as "systemIndigoColor".
    static func color(named name: String?) -> Color? {
        guard var key = name?.lowercased() else { return nil }
        if key.hasPrefix("system") { key.removeFirst("system".count) }
        if key.hasSuffix("color") { key.removeLast("color".count) }
        switch key {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        default: return nil
        }
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    @MainActor
    private static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
