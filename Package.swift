// swift-tools-version: 6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
]

let package = Package(
    name: "Notch",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Notch", targets: ["Notch"]),
    ],
    targets: [
        .target(name: "NotchCore", swiftSettings: swiftSettings),

        // Feature modules depend only on NotchCore so each builds in isolation.
        .target(name: "NotchMedia", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchHUD", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchSystem", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchLock", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchCalendar", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "NotchFileTray", dependencies: ["NotchCore"], swiftSettings: swiftSettings),

        .executableTarget(
            name: "Notch",
            dependencies: [
                "NotchCore", "NotchMedia", "NotchHUD", "NotchSystem",
                "NotchLock", "NotchCalendar", "NotchFileTray",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
