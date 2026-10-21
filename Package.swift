// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Switchboard",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Switchboard", path: "Sources/Switchboard")
    ]
)
