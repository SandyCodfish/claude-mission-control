// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeMissionControl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeMissionControl",
            path: "Sources/ClaudeMissionControl",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "ClaudeMissionControlTests",
            dependencies: ["ClaudeMissionControl"],
            path: "Tests/ClaudeMissionControlTests"
        )
    ]
)
