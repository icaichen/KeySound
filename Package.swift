// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeySound",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KeySound",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("Sounds"),
                .copy("Recipes")
            ]
        )
    ]
)