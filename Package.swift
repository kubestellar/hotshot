// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "hotshot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "hotshot",
            path: "Sources"
        )
    ]
)
