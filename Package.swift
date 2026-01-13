// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gaffer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Gaffer",
            path: "Gaffer",
            exclude: ["Info.plist", "Assets.xcassets"]
        )
    ]
)
