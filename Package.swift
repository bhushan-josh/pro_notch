// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "ProNotch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ProNotch", targets: ["ProNotch"]),
    ],
    targets: [
        .target(name: "NotchCore", swiftSettings: swiftSettings),

        // Feature modules depend only on NotchCore so each builds in isolation.
        .target(name: "NotchMedia", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchHUD", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchSystem", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchLock", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchCalendar", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchDownloads", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchTimers", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchClipboard", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchStats", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchKeepAwake", dependencies: ["NotchCore"], swiftSettings: swiftSettings),

        .executableTarget(
            name: "ProNotch",
            dependencies: [
                "NotchCore", "NotchMedia", "NotchHUD", "NotchSystem",
                "NotchLock", "NotchCalendar", "NotchDownloads",
                "NotchTimers", "NotchClipboard", "NotchStats", "NotchKeepAwake",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
