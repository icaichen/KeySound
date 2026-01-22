// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "KeyboardSoundSimulator",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KeyboardSoundSimulator",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("Sounds")
            ]
        )
    ]
)