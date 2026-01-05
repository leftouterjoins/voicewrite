// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceWrite",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VoiceWrite", targets: ["VoiceWrite"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceWrite",
            dependencies: [
                "KeyboardShortcuts",
                "Sparkle",
            ],
            path: "VoiceWrite",
            exclude: ["Info.plist", "VoiceWrite.entitlements"]
        ),
    ]
)
