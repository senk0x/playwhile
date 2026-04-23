// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlayWhile",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PlayWhile",
            path: "Sources/VibeGames"
        )
    ]
)
