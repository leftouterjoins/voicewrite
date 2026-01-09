// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceWrite",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VoiceWrite", targets: ["VoiceWrite"]),
        .executable(name: "VoiceWriteInputMethod", targets: ["VoiceWriteInputMethod"])
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
            exclude: ["Info.plist", "VoiceWrite.entitlements", "icon@3x.png", "AppIcon.icns"]
        ),
        .executableTarget(
            name: "VoiceWriteInputMethod",
            dependencies: [],
            path: "VoiceWriteInputMethod",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
            ]
        ),
    ]
)
