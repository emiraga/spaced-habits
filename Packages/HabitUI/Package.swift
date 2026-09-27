// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HabitUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "HabitUI", targets: ["HabitUI"]),
    ],
    dependencies: [
        .package(path: "../HabitCore"),
        .package(path: "../HabitStore"),
    ],
    targets: [
        .target(
            name: "HabitUI",
            dependencies: ["HabitCore", "HabitStore"],
            resources: [.process("Resources")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "HabitUITests",
            dependencies: ["HabitUI", .product(name: "HabitSimulation", package: "HabitCore")],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ]
)
