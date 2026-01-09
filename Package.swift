// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceWrite",
    defaultLocalization: "en",
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
            exclude: ["Info.plist", "VoiceWrite.entitlements", "icon@3x.png", "AppIcon.icns"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/fr.lproj"),
                .process("Resources/de.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/it.lproj"),
                .process("Resources/pt-BR.lproj"),
                .process("Resources/ko.lproj"),
                .process("Resources/ru.lproj")
            ]
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
