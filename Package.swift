// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LiveCue",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "LiveCue",
            path: "Sources/Talkback",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
