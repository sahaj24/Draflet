// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIWritingAssistant",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AIWritingAssistant",
            targets: ["AIWritingAssistant"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AIWritingAssistant",
            dependencies: [],
            path: "Sources",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
    ]
)
