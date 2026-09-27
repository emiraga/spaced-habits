// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HabitCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HabitCore", targets: ["HabitCore"]),
        // For HabitUI's chart tests (generated fixtures); not linked by the apps.
        .library(name: "HabitSimulation", targets: ["HabitSimulation"]),
        .executable(name: "simulate", targets: ["simulate"]),
    ],
    targets: [
        .target(
            name: "HabitCore",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // §4.8 synthetic users driving the engine; shared by the tests and `simulate`.
        .target(
            name: "HabitSimulation",
            dependencies: ["HabitCore"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .executableTarget(
            name: "simulate",
            dependencies: ["HabitSimulation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "HabitCoreTests",
            dependencies: ["HabitCore", "HabitSimulation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
