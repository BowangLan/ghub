// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GHub", targets: ["GHub"])
    ],
    targets: [
        .executableTarget(
            name: "GHub",
            path: "Sources/GHub",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
