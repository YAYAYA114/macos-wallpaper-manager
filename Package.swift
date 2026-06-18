// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WallpaperManager",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WallpaperManager",
            path: "Sources/WallpaperManager",
            resources: [.process("Resources")]
        )
    ]
)
